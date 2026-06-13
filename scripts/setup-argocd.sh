#!/usr/bin/env bash
# Patches the ArgoCD admin password to "password" and logs in via CLI.
set -euo pipefail

NAMESPACE=argocd
TARGET_PASS=password

echo "==> Waiting for ArgoCD server pod..."
kubectl wait --for=condition=Ready pod \
  -l app.kubernetes.io/name=argocd-server \
  -n "$NAMESPACE" --timeout=120s

echo "==> Patching admin password (bcrypt of '$TARGET_PASS')..."
BCRYPT_HASH='$2a$10$rRyBsGSHK6.uf6/7CFLMoe7P/OFKQiKIrIr0zKxLUTNYP5Oq3rIuO'
kubectl -n "$NAMESPACE" patch secret argocd-secret \
  -p "{\"stringData\":{\"admin.password\":\"${BCRYPT_HASH}\",\"admin.passwordMtime\":\"$(date +%FT%T%Z)\"}}"

echo "==> Port-forwarding ArgoCD server (background)..."
kubectl port-forward svc/argocd-server -n "$NAMESPACE" 8443:443 &>/dev/null &
PF_PID=$!
sleep 3

echo "==> Logging in via argocd CLI..."
argocd login localhost:8443 \
  --username admin \
  --password "$TARGET_PASS" \
  --insecure \
  --grpc-web 2>/dev/null || true

kill "$PF_PID" 2>/dev/null || true
echo "==> ArgoCD setup complete. admin / $TARGET_PASS"
