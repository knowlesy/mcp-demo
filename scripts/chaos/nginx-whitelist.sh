#!/usr/bin/env bash
# Scenario 3: Add an IP whitelist annotation that blocks all external traffic.
set -euo pipefail

APP_NS=apps
INGRESS_NAME=dummy-webapp
# Block all IPs except an RFC-5737 test address no real client will have
BLOCKED_CIDR="203.0.113.1/32"

echo "==> [Whitelist] Applying restrictive nginx whitelist to Ingress '$INGRESS_NAME'..."
kubectl annotate ingress "$INGRESS_NAME" -n "$APP_NS" \
  "nginx.ingress.kubernetes.io/whitelist-source-range=${BLOCKED_CIDR}" \
  --overwrite

echo ""
echo "==> [Whitelist] Waiting 5s for nginx to reload..."
sleep 5

echo ""
echo "==> [Whitelist] Testing access (expect 403):"
curl -sf -o /dev/null -w "HTTP Status: %{http_code}\n" http://app.local/ || \
  echo "HTTP Status: 403 (or connection refused — whitelist is active)"

echo ""
echo "==> Chaos Scenario 3 complete."
echo "    Read docs/runbooks/03-nginx-whitelist.md to resolve."
