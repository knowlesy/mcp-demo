# Runbook Overview — MCP Demo Chaos Sandbox

This directory contains Standard Operating Procedures (SOPs) written for Claude to read
via the **Filesystem MCP**. Each runbook is structured with explicit tool-call suggestions
so Claude can follow a machine-readable remediation path.

## Agentic Loop Pattern

Claude should follow this sequence for every incident:

```
STEP 1 — DETECT
  Tool: Kubernetes MCP
  Action: kubectl get pods -A | kubectl describe pod <name> | kubectl get events

STEP 2 — READ SOP
  Tool: Filesystem MCP
  Action: read docs/runbooks/<N>-<scenario>.md

STEP 3 — DIAGNOSE
  Tool: Prometheus MCP / Grafana MCP
  Action: query relevant metric, read dashboard panel

STEP 4 — RECORD HYPOTHESIS
  Tool: Memory MCP
  Action: store { incident_type, affected_resource, timestamp, hypothesis }

STEP 5 — APPLY FIX
  Tool: varies by scenario (Git, ArgoCD, Ansible, Rundeck, SQLite, Bash)
  Action: follow the RESOLUTION steps in the runbook

STEP 6 — VERIFY
  Tool: Bash MCP / Kubernetes MCP
  Action: curl /health, kubectl get pods, check metrics

STEP 7 — REPORT
  Tool: Slack MCP
  Action: post summary to #incidents channel
```

## Runbook Index

| File | Scenario | Primary Fix MCPs |
|------|----------|-----------------|
| [01-oom-kill.md](01-oom-kill.md) | OOM Kill | Kubernetes, Git, ArgoCD |
| [02-rundeck-chaos.md](02-rundeck-chaos.md) | Deleted Deployment | Rundeck, Kubernetes, ArgoCD |
| [03-nginx-whitelist.md](03-nginx-whitelist.md) | IP Whitelist Block | Bash, Kubernetes, Ansible |
| [04-traffic-spike.md](04-traffic-spike.md) | High Traffic Spike | Prometheus, Git, ArgoCD |
| [05-db-corruption.md](05-db-corruption.md) | SQLite Corruption | Bash, SQLite, Rundeck |

## Common Kubectl Commands (Reference)

```bash
# Pod status across all namespaces
kubectl get pods -A

# Describe a specific pod (includes events, resource limits, last state)
kubectl describe pod <pod-name> -n <namespace>

# Recent cluster events (sorted by time)
kubectl get events -A --sort-by='.lastTimestamp'

# Exec into a running container
kubectl exec -it <pod-name> -n <namespace> -- /bin/sh

# Tail logs
kubectl logs -f <pod-name> -n <namespace>

# Force pod restart
kubectl rollout restart deployment/<name> -n <namespace>
```
