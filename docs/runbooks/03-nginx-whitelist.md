# SOP-03: Nginx IP Whitelist Block

**Severity:** P2 — All external traffic returning 403 Forbidden  
**Likely Trigger:** `make chaos-nginx` added a restrictive `whitelist-source-range` annotation  
**Primary MCPs:** Bash, Kubernetes, Ansible, Memory, Slack

---

## Symptoms

- `curl http://app.local/` returns `HTTP 403 Forbidden`
- nginx logs show `access forbidden by rule`
- Prometheus metric `webapp_requests_total` drops to zero (no requests reaching the app)
- Grafana "Request Rate" panel flatlines

---

## Diagnosis Steps

### Step 1 — Confirm 403 via Bash MCP

```bash
curl -v http://app.local/
```

Expected broken response:
```
< HTTP/1.1 403 Forbidden
< Content-Type: text/html
```

### Step 2 — Inspect the Ingress annotation via Kubernetes MCP

```bash
kubectl get ingress dummy-webapp -n apps -o yaml
```

Look for the offending annotation:
```yaml
metadata:
  annotations:
    nginx.ingress.kubernetes.io/whitelist-source-range: "203.0.113.1/32"
```

This CIDR is an RFC 5737 documentation address — no real client will match it,
effectively blocking all traffic.

### Step 3 — Check nginx ingress controller logs

```bash
kubectl logs -n ingress-nginx \
  $(kubectl get pod -n ingress-nginx -l app.kubernetes.io/component=controller -o jsonpath='{.items[0].metadata.name}') \
  | grep "access forbidden" | tail -10
```

### Step 4 — Store diagnosis in Memory MCP

```json
{
  "incident": "Nginx IP Whitelist Block",
  "resource": "ingress/dummy-webapp",
  "namespace": "apps",
  "cause": "whitelist-source-range annotation set to 203.0.113.1/32 — blocks all clients",
  "fix": "remove the whitelist-source-range annotation"
}
```

---

## Resolution

### Option A — Automated (Ansible)

```bash
ansible-playbook -i ansible/inventory/localhost.ini ansible/playbooks/fix-nginx-whitelist.yaml
```

### Option B — Manual via Kubernetes MCP

**Step 1:** Remove the whitelist annotation (the trailing `-` removes the key)

```bash
kubectl annotate ingress dummy-webapp -n apps \
  nginx.ingress.kubernetes.io/whitelist-source-range-
```

**Step 2:** Confirm the annotation is gone

```bash
kubectl get ingress dummy-webapp -n apps \
  -o jsonpath='{.metadata.annotations.nginx\.ingress\.kubernetes\.io/whitelist-source-range}'
# Expected: (empty)
```

**Step 3:** Wait 5 seconds for nginx to reload its config

```bash
sleep 5
```

---

## Verification

```bash
curl -sf -o /dev/null -w "%{http_code}" http://app.local/
# Expected: 200

curl -sf http://app.local/health
# Expected: {"status": "healthy", "db": "ok"}
```

Prometheus verification (traffic should resume):
```promql
rate(webapp_requests_total[2m])
```

Should show a non-zero value within 2 minutes.

---

## Post-Incident

- If a real IP restriction is needed in future, document the CIDR in `docs/runbooks/` before applying
- Post resolution summary to `#incidents` via Slack MCP
- Update Memory MCP: mark resolved, note the annotation path for future reference
