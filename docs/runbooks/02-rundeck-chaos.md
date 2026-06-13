# SOP-02: Rundeck Chaos — Deleted or Corrupted Deployment

**Severity:** P1 — Service completely down  
**Likely Trigger:** Rundeck job `chaos-delete-deployment` or `chaos-corrupt-configmap` was executed  
**Primary MCPs:** Kubernetes, Rundeck, Ansible, ArgoCD, Memory, Slack

---

## Symptoms

- `kubectl get pods -n apps` shows no pods, or all pods in `CrashLoopBackOff`
- ArgoCD Application status: `Degraded` or `OutOfSync`
- `/health` returns 503 or connection refused
- Rundeck job execution history shows a recent chaos job run

---

## Diagnosis Steps

### Step 1 — Check pod and deployment state via Kubernetes MCP

```bash
kubectl get pods -n apps
kubectl get deployment dummy-webapp -n apps
kubectl get events -n apps --sort-by='.lastTimestamp' | tail -20
```

If the deployment is missing:
```
Error from server (NotFound): deployments.apps "dummy-webapp" not found
```

### Step 2 — Inspect ArgoCD status via ArgoCD MCP

```bash
argocd app get dummy-webapp --grpc-web --insecure
```

Look for:
- `Health Status: Degraded`
- `Sync Status: OutOfSync`
- Missing resources listed in the diff

### Step 3 — Check Rundeck execution history via Rundeck MCP

Navigate to Rundeck → Project: mcp-demo → Activity tab.

Look for recent executions of:
- `chaos-delete-deployment`
- `chaos-corrupt-configmap`

Note the execution timestamp to determine when the incident started.

### Step 4 — Check ConfigMap for corruption

```bash
kubectl get configmap dummy-webapp-config -n apps -o yaml
```

If `DB_PATH` is `/nonexistent/path/app.db` → ConfigMap corruption scenario.

---

## Resolution

### Scenario A: Deployment deleted

**Option 1 — Let ArgoCD self-heal** (if `selfHeal: true` is configured, wait 30-60s)

```bash
argocd app get dummy-webapp --grpc-web --insecure
# Wait for Sync Status to return to Synced
```

**Option 2 — Force sync via ArgoCD MCP**

```bash
argocd app sync dummy-webapp --force --grpc-web --insecure
argocd app wait dummy-webapp --sync --health --timeout 120
```

**Option 3 — Ansible playbook**

```bash
ansible-playbook -i ansible/inventory/localhost.ini ansible/playbooks/fix-rundeck-chaos.yaml
```

### Scenario B: ConfigMap corrupted

**Step 1:** Restore the ConfigMap via Kubernetes MCP

```bash
kubectl patch configmap dummy-webapp-config -n apps \
  --type=json \
  -p='[{"op":"replace","path":"/data/DB_PATH","value":"/data/app.db"}]'
```

**Step 2:** Restart the deployment to pick up the corrected config

```bash
kubectl rollout restart deployment/dummy-webapp -n apps
kubectl rollout status deployment/dummy-webapp -n apps
```

---

## Verification

```bash
kubectl get pods -n apps -l app=dummy-webapp
# Expected: 1/1 Running

curl -sf http://app.local/health
# Expected: {"status": "healthy", "db": "ok"}
```

---

## Post-Incident

- Document the Rundeck job execution ID in Memory MCP
- Consider adding a K8s `ResourceQuota` or RBAC restriction to prevent accidental deletes
- Post summary to `#incidents` Slack channel via Slack MCP
