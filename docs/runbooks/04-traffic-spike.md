# SOP-04: High Traffic Spike — Scale Out

**Severity:** P2 — Elevated latency, potential pod saturation  
**Likely Trigger:** `make chaos-traffic` running `hey` at 50 RPS against 1 replica  
**Primary MCPs:** Prometheus, Grafana, Git, ArgoCD, Memory, Slack

---

## Symptoms

- Grafana "Request Latency p95" panel spikes above 500ms
- Prometheus `webapp_requests_total` rate is high but errors are increasing
- `kubectl top pods -n apps` shows CPU near limit
- Response times feel slow or requests are timing out

---

## Diagnosis Steps

### Step 1 — Query Prometheus for traffic rate via Prometheus MCP

```promql
rate(webapp_requests_total[1m])
```

Compare with baseline. A spike scenario typically shows 20-50x normal rate.

### Step 2 — Check p95 latency

```promql
histogram_quantile(0.95,
  rate(webapp_request_latency_seconds_bucket[2m])
)
```

If > 0.5s, the single replica is saturated.

### Step 3 — Check CPU utilisation

```promql
rate(container_cpu_usage_seconds_total{namespace="apps", container="webapp"}[2m])
```

If approaching `200m` (the CPU limit), the pod is CPU-throttled.

### Step 4 — Check current replica count via Kubernetes MCP

```bash
kubectl get deployment dummy-webapp -n apps
```

Expected (broken state): `READY 1/1` — only one replica serving all traffic.

### Step 5 — Check Grafana dashboard

Open: http://grafana.local → Dashboard: "Kubernetes / Compute Resources / Pod"  
Look at: Request Rate, CPU Throttling, Memory Usage panels.

---

## Resolution

Scale the deployment to 3 replicas. Two approaches:

### Option A — Automated (Ansible)

```bash
ansible-playbook -i ansible/inventory/localhost.ini ansible/playbooks/fix-traffic-spike.yaml
```

This updates `deployment.yaml`, commits to Gitea, and triggers ArgoCD sync.

### Option B — Git + ArgoCD (GitOps path — recommended for demo)

**Step 1:** Update replica count in `apps/dummy-webapp/k8s/deployment.yaml` via Git MCP

Change:
```yaml
spec:
  replicas: 1
```
To:
```yaml
spec:
  replicas: 3
```

**Step 2:** Commit and push

```bash
git add apps/dummy-webapp/k8s/deployment.yaml
git commit -m "fix(traffic): scale to 3 replicas during high traffic"
git push gitea main
```

**Step 3:** Sync via ArgoCD MCP

```bash
argocd app sync dummy-webapp --grpc-web --insecure
argocd app wait dummy-webapp --sync --health --timeout 120
```

**Step 4:** Confirm 3 replicas are ready

```bash
kubectl get pods -n apps -l app=dummy-webapp
# Expected: 3 pods, all Running
```

---

## Verification

```bash
kubectl get deployment dummy-webapp -n apps
# Expected: READY 3/3

# Check latency has dropped
# Prometheus query:
# histogram_quantile(0.95, rate(webapp_request_latency_seconds_bucket[2m]))
# Expected: < 0.1s
```

---

## Scale-Down (after spike ends)

Once traffic normalises, revert replicas to 1 to conserve resources:

```bash
# Edit deployment.yaml: replicas: 1
git add apps/dummy-webapp/k8s/deployment.yaml
git commit -m "chore: scale dummy-webapp back to 1 replica post-spike"
git push gitea main
argocd app sync dummy-webapp --grpc-web --insecure
```

---

## Post-Incident

- Post Slack summary with peak RPS, max p95 latency, and resolution time
- Consider adding a HorizontalPodAutoscaler (HPA) to automate scale-out
- Update Memory MCP with incident details and resolution timestamp
