#!/usr/bin/env bash
# Imports all Rundeck job definitions from rundeck/jobs/ via the API.
set -euo pipefail

RUNDECK_NS=rundeck
RUNDECK_USER=admin
RUNDECK_PASS=password
RUNDECK_PROJECT=mcp-demo
JOBS_DIR="$(dirname "$0")/../rundeck/jobs"

echo "==> Waiting for Rundeck pod..."
kubectl wait --for=condition=Ready pod \
  -l app.kubernetes.io/name=rundeck \
  -n "$RUNDECK_NS" --timeout=180s

echo "==> Port-forwarding Rundeck (background)..."
kubectl port-forward svc/rundeck -n "$RUNDECK_NS" 4440:4440 &>/dev/null &
PF_PID=$!
sleep 8

RD_URL="http://localhost:4440"

echo "==> Obtaining Rundeck API token..."
TOKEN=$(curl -sf -X POST "${RD_URL}/j_security_check" \
  -c /tmp/rd_cookies.txt \
  -d "j_username=${RUNDECK_USER}&j_password=${RUNDECK_PASS}" \
  -L -w "%{url_effective}" -o /dev/null \
  | grep -o 'authtoken=[^&]*' | cut -d= -f2 || true)

# Fallback: use basic auth header approach for newer Rundeck versions
AUTH_HEADER="Authorization: Basic $(echo -n "${RUNDECK_USER}:${RUNDECK_PASS}" | base64)"

echo "==> Creating Rundeck project '$RUNDECK_PROJECT'..."
curl -sf -X POST "${RD_URL}/api/41/projects" \
  -H "$AUTH_HEADER" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"${RUNDECK_PROJECT}\",\"description\":\"MCP Demo chaos and fix jobs\"}" \
  && echo "Project created." \
  || echo "Project may already exist — continuing."

sleep 2

echo "==> Importing job definitions..."
for job_file in "$JOBS_DIR"/*.yaml; do
  echo "  -> Importing $job_file ..."
  curl -sf -X POST "${RD_URL}/api/41/project/${RUNDECK_PROJECT}/jobs/import" \
    -H "$AUTH_HEADER" \
    -H "Content-Type: application/yaml" \
    --data-binary "@${job_file}" \
    -o /dev/null
done

kill "$PF_PID" 2>/dev/null || true
echo "==> Rundeck setup complete. Login: ${RUNDECK_USER} / ${RUNDECK_PASS}"
