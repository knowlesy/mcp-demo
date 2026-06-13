# SOP-01: OOM Kill — dummy-webapp

**Severity:** P2 — Pod crash-looping, service unavailable  
**Likely Trigger:** `/stress` endpoint called, or application memory leak  
**Primary MCPs:** Kubernetes, Filesystem, Git, ArgoCD, Memory, Slack

---

## Symptoms

- `kubectl get pods -n apps` shows `OOMKilled` under `RESTARTS` or `STATUS`
- `/health` endpoint returns connection refused or 503
- Prometheus metric `kube_pod_container_status_last_terminated_reason{reason="OOMKilled"}` == 1
- Grafana "Container Memory Usage" panel shows memory hitting the limit ceiling

---

## Diagnosis Steps

### Step 1 — Confirm OOMKill via Kubernetes MCP

```bash
kubectl get pods -n apps -l app=dummy-webapp
kubectl describe pod -n apps -l app=dummy-webapp
```

Look for:
```
Last State:     Terminated
  Reason:       OOMKilled
  Exit Code:    137
```

Exit code 137 = SIGKILL sent by the OOM killer.

### Step 2 — Check resource limits

```bash
kubectl get deployment dummy-webapp -n apps -o jsonpath='{.spec.template.spec.containers[0].resources}'
```

Expected (broken state): `"limits":{"cpu":"200m","memory":"256Mi"}`

### Step 3 — Confirm via Prometheus MCP

Query:
```promql
kube_pod_container_status_last_terminated_reason{
  namespace="apps",
  container="webapp",
  reason="OOMKilled"
}
```

Should return `1` during the incident.

Also check peak memory usage before the kill:
```promql
max_over_time(
  container_memory_usage_bytes{namespace="apps", container="webapp"}[10m]
) / 1024 / 1024
```

### Step 4 — Store hypothesis in Memory MCP

```json
{
  "incident": "OOM Kill",
  "resource": "deployment/dummy-webapp",
  "namespace": "apps",
  "cause": "memory limit 256Mi too low — pod consumed >256Mi and was OOMKilled",
  "fix": "raise limits.memory to 512Mi, commit to Gitea, sync ArgoCD"
}
```

---

## Resolution

### Option A — Automated (Ansible)

```bash
ansible-playbook -i ansible/inventory/localhost.ini ansible/playbooks/fix-oom.yaml
```

### Option B — Manual via Git MCP + ArgoCD MCP

**Step 1:** Update `apps/dummy-webapp/k8s/deployment.yaml`

Change:
```yaml
        limits:
          cpu: 200m
          memory: 256Mi
```
To:
```yaml
        limits:
          cpu: 200m
          memory: 512Mi
```

**Step 2:** Commit and push via Git MCP

```bash
git add apps/dummy-webapp/k8s/deployment.yaml
git commit -m "fix(oom): raise memory limit to 512Mi"
git push gitea main
```

**Step 3:** Trigger ArgoCD sync via ArgoCD MCP

```bash
argocd app sync dummy-webapp --grpc-web --insecure
argocd app wait dummy-webapp --sync --health --timeout 120
```

**Step 4:** Verify pod is running without OOMKill

```bash
kubectl get pods -n apps -l app=dummy-webapp
kubectl describe pod -n apps -l app=dummy-webapp | grep "Last State"
```

Expected: no `OOMKilled` in Last State.

---

## Verification

```bash
curl -sf http://app.local/health
# Expected: {"status": "healthy", "db": "ok"}
```

Prometheus verification:
```promql
kube_pod_container_status_last_terminated_reason{reason="OOMKilled",namespace="apps"}
# Expected: 0 or no data
```

---

## Post-Incident

- Report to Slack via Slack MCP: `#incidents` channel
- Update Memory MCP: mark incident resolved, record new limit value
- Consider adding a Prometheus alert for `container_memory_usage_bytes > 0.9 * limit`
