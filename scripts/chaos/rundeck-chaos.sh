#!/usr/bin/env bash
# Scenario 2: Trigger the chaos Rundeck job via its API.
# The job deletes the dummy-webapp Deployment, simulating an accidental ops action.
set -euo pipefail

RUNDECK_NS=rundeck
RUNDECK_USER=admin
RUNDECK_PASS=password
RUNDECK_PROJECT=mcp-demo
JOB_NAME="chaos-delete-deployment"

echo "==> [Rundeck Chaos] Port-forwarding Rundeck..."
kubectl port-forward svc/rundeck -n "$RUNDECK_NS" 4440:4440 &>/dev/null &
PF_PID=$!
sleep 4

RD_URL="http://localhost:4440"
AUTH_HEADER="Authorization: Basic $(echo -n "${RUNDECK_USER}:${RUNDECK_PASS}" | base64)"

echo "==> [Rundeck Chaos] Looking up job ID for '$JOB_NAME'..."
JOB_ID=$(curl -sf "${RD_URL}/api/41/project/${RUNDECK_PROJECT}/jobs" \
  -H "$AUTH_HEADER" \
  -H "Accept: application/json" \
  | python3 -c "
import sys, json
jobs = json.load(sys.stdin)
for j in jobs:
    if j.get('name') == '${JOB_NAME}':
        print(j['id'])
        break
" 2>/dev/null || true)

if [ -z "$JOB_ID" ]; then
  echo "ERROR: Job '$JOB_NAME' not found. Did you run 'make deploy-infra'?"
  kill "$PF_PID" 2>/dev/null || true
  exit 1
fi

echo "==> [Rundeck Chaos] Executing job ID: $JOB_ID ..."
EXEC_ID=$(curl -sf -X POST "${RD_URL}/api/41/job/${JOB_ID}/run" \
  -H "$AUTH_HEADER" \
  -H "Content-Type: application/json" \
  -d '{}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")

echo "    Execution ID: $EXEC_ID"
echo ""

kill "$PF_PID" 2>/dev/null || true

echo "==> Waiting 10s for deployment to be deleted..."
sleep 10

echo "==> [Rundeck Chaos] Current pod state:"
kubectl get pods -n apps
echo ""
echo "==> Chaos Scenario 2 complete."
echo "    Read docs/runbooks/02-rundeck-chaos.md to resolve."
