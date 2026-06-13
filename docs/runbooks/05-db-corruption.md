# SOP-05: SQLite Database Corruption — Missing Tables

**Severity:** P1 — Application completely non-functional; all data endpoints broken  
**Likely Trigger:** `make chaos-db` dropped the `users` and `events` tables  
**Primary MCPs:** Bash, Kubernetes, SQLite, Rundeck, Ansible, Memory, Slack

---

## Symptoms

- `GET /health` returns `HTTP 500` with body `{"status": "unhealthy", "db": "no such table: users"}`
- `GET /users` returns `HTTP 500` with body `{"error": "no such table: users"}`
- Prometheus metric `webapp_db_errors_total` is incrementing
- Grafana "DB Error Rate" panel shows non-zero errors
- Pod is running and not restarting (this is NOT an OOM — the container is healthy, the data is corrupt)

---

## Diagnosis Steps

### Step 1 — Confirm the symptom via Bash MCP

```bash
curl -sf http://app.local/health
```

Expected broken response:
```json
{"status": "unhealthy", "db": "no such table: users"}
```

```bash
curl -sf http://app.local/users
```

Expected broken response:
```json
{"error": "no such table: users"}
```

### Step 2 — Confirm pod is running (not crashing) via Kubernetes MCP

```bash
kubectl get pods -n apps -l app=dummy-webapp
```

Expected: `1/1 Running` — the pod IS running; the problem is data, not the container.

```bash
kubectl describe pod -n apps -l app=dummy-webapp | grep -A 5 "State:"
```

Expected: `State: Running` with no OOMKill in Last State. This distinguishes
Scenario 5 from Scenario 1.

### Step 3 — Inspect the SQLite database via SQLite MCP

Get the pod name first:
```bash
kubectl get pod -n apps -l app=dummy-webapp -o jsonpath='{.items[0].metadata.name}'
```

Open a SQLite session inside the pod:
```bash
kubectl exec -n apps <POD_NAME> -- sqlite3 /data/app.db
```

Inside SQLite, run:
```sql
.tables
```

**Broken state — expected output:**
```
(empty — no tables listed)
```

**Healthy state — expected output:**
```
events  users
```

Confirm missing table:
```sql
SELECT name FROM sqlite_master WHERE type='table';
```

If output is empty, both tables are missing. This confirms the corruption scenario.

Also check the database file exists:
```sql
.databases
```

If the file is present but `.tables` is empty, the schema was dropped without deleting the file.

### Step 4 — Check Prometheus DB error counter via Prometheus MCP

```promql
increase(webapp_db_errors_total[5m])
```

A non-zero value confirms the app is experiencing database errors.

### Step 5 — Record in Memory MCP

```json
{
  "incident": "SQLite DB Corruption",
  "resource": "pod/dummy-webapp",
  "namespace": "apps",
  "db_path": "/data/app.db",
  "missing_tables": ["users", "events"],
  "cause": "DROP TABLE executed via kubectl exec (chaos-db scenario)",
  "diagnosis_timestamp": "<ISO8601 timestamp>",
  "fix": "restore schema via CREATE TABLE IF NOT EXISTS, re-seed data"
}
```

---

## Resolution

Three options are available. Choose based on tool access:

### Option A — Automated Ansible Playbook (Recommended)

```bash
ansible-playbook -i ansible/inventory/localhost.ini ansible/playbooks/fix-db-corruption.yaml
```

This playbook:
1. Confirms `/health` returns 500
2. Gets the pod name
3. Executes `CREATE TABLE IF NOT EXISTS` for both tables
4. Seeds initial data (Admin, Alice)
5. Verifies `/health` returns 200
6. Verifies `/users` returns data

### Option B — Rundeck Job

1. Open Rundeck: http://rundeck.local:4440
2. Navigate to: Project `mcp-demo` → Jobs → `db-restore`
3. Click **Run Job Now**
4. Monitor the execution log for:
   ```
   Schema restored
   {"status": "healthy", "db": "ok"}
   ```

Via Rundeck MCP:
```bash
# Get the job ID
curl -s http://localhost:4440/api/41/project/mcp-demo/jobs \
  -H "Authorization: Basic $(echo -n admin:password | base64)" \
  -H "Accept: application/json" \
  | python3 -c "import sys,json; [print(j['id']) for j in json.load(sys.stdin) if j['name']=='db-restore']"

# Run it
curl -sf -X POST http://localhost:4440/api/41/job/<JOB_ID>/run \
  -H "Authorization: Basic $(echo -n admin:password | base64)" \
  -H "Content-Type: application/json" \
  -d '{}'
```

### Option C — Manual via SQLite MCP + Kubernetes MCP

**Step 1:** Exec into the pod

```bash
kubectl exec -it -n apps \
  $(kubectl get pod -n apps -l app=dummy-webapp -o jsonpath='{.items[0].metadata.name}') \
  -- /bin/sh
```

**Step 2:** Restore the schema using SQLite MCP (or Python inside the pod)

```bash
python3 << 'EOF'
import sqlite3, os
db = os.environ.get('DB_PATH', '/data/app.db')
conn = sqlite3.connect(db)
conn.executescript("""
    CREATE TABLE IF NOT EXISTS users (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        name       TEXT    NOT NULL,
        email      TEXT    UNIQUE NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    CREATE TABLE IF NOT EXISTS events (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id    INTEGER,
        action     TEXT,
        timestamp  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (user_id) REFERENCES users(id)
    );
""")
conn.execute("INSERT OR IGNORE INTO users (name, email) VALUES ('Admin', 'admin@example.com')")
conn.execute("INSERT OR IGNORE INTO users (name, email) VALUES ('Alice', 'alice@example.com')")
conn.commit()
rows = conn.execute('SELECT COUNT(*) FROM users').fetchone()
print(f"Restore complete. users table has {rows[0]} rows.")
conn.close()
EOF
```

**Step 3:** Exit the pod and verify

```bash
exit
curl -sf http://app.local/health
```

---

## Alternative: Pod Restart (Quick but loses SQLite data)

Because the app calls `init_db()` on startup, a pod restart will recreate the schema.
**Warning:** This only works because we use `emptyDir` storage — the SQLite file is in
the pod's ephemeral filesystem. In a production scenario with a PVC, the file would
persist and a restart would NOT fix it. This distinction is important for the MCP agent
to understand.

```bash
kubectl rollout restart deployment/dummy-webapp -n apps
kubectl rollout status deployment/dummy-webapp -n apps
```

Use this only if the exec-based restore fails.

---

## Verification

### Bash MCP checks

```bash
curl -sf http://app.local/health
# Expected: {"status": "healthy", "db": "ok"}

curl -sf http://app.local/users
# Expected: [{"id":1,"name":"Admin","email":"admin@example.com",...}, ...]
```

### SQLite MCP checks (inside pod)

```bash
kubectl exec -n apps \
  $(kubectl get pod -n apps -l app=dummy-webapp -o jsonpath='{.items[0].metadata.name}') \
  -- sqlite3 /data/app.db ".tables"
# Expected: events  users

kubectl exec -n apps \
  $(kubectl get pod -n apps -l app=dummy-webapp -o jsonpath='{.items[0].metadata.name}') \
  -- sqlite3 /data/app.db "SELECT COUNT(*) FROM users;"
# Expected: 2
```

### Prometheus MCP check

```promql
increase(webapp_db_errors_total[2m])
```

Should be 0 or decreasing to 0 within 2 minutes of the fix.

---

## Root Cause Analysis Notes

| Field | Value |
|-------|-------|
| Blast Radius | 100% of write and read operations fail |
| Data Loss | Yes — all rows in `users` and `events` are gone |
| MTTR (manual) | ~5 minutes |
| MTTR (automated) | ~60 seconds |
| Prevention | Add K8s RBAC to restrict `kubectl exec` in production |

---

## Post-Incident Actions

1. **Slack MCP** — Post to `#incidents`:
   ```
   [RESOLVED] SQLite DB corruption on dummy-webapp (apps namespace).
   Cause: DROP TABLE via kubectl exec (chaos test).
   Tables restored. Downtime: ~X minutes.
   Action: Schema + seed data restored via db-restore Rundeck job.
   ```

2. **Memory MCP** — Update incident record:
   ```json
   {
     "incident": "SQLite DB Corruption",
     "status": "resolved",
     "resolution": "schema restored via Ansible/Rundeck",
     "downtime_minutes": "<N>",
     "resolved_timestamp": "<ISO8601>"
   }
   ```

3. **Git MCP** — If adding a backup cron job, commit the CronJob manifest:
   ```bash
   # Consider: a K8s CronJob that runs `sqlite3 /data/app.db .dump > /backup/app-$(date).sql`
   # every 15 minutes and mounts a PVC for backup storage.
   ```
