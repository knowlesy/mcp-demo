#!/usr/bin/env bash
# Creates the mcp-demo repo in Gitea and pushes k8s manifests to it.
set -euo pipefail

GITEA_NS=gitea
GITEA_USER=gitadmin
GITEA_PASS=password
REPO_NAME=mcp-demo

echo "==> Waiting for Gitea pod..."
kubectl wait --for=condition=Ready pod \
  -l app.kubernetes.io/name=gitea \
  -n "$GITEA_NS" --timeout=120s

echo "==> Port-forwarding Gitea (background)..."
kubectl port-forward svc/gitea-http -n "$GITEA_NS" 3300:3000 &>/dev/null &
PF_PID=$!
sleep 4

GITEA_URL="http://localhost:3300"

echo "==> Creating repo '$REPO_NAME' in Gitea..."
curl -sf -X POST "${GITEA_URL}/api/v1/user/repos" \
  -u "${GITEA_USER}:${GITEA_PASS}" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"${REPO_NAME}\",\"private\":false,\"auto_init\":true}" \
  && echo "Repo created." \
  || echo "Repo may already exist — continuing."

sleep 2

echo "==> Pushing repo contents to Gitea..."
# Set up a temporary remote pointing at the port-forward
git remote remove gitea 2>/dev/null || true
git remote add gitea "http://${GITEA_USER}:${GITEA_PASS}@localhost:3300/${GITEA_USER}/${REPO_NAME}.git"
git push gitea HEAD:main --force

kill "$PF_PID" 2>/dev/null || true
git remote remove gitea 2>/dev/null || true

echo "==> Gitea push complete."
