#!/usr/bin/env bash
# Scenario 4: Generate a traffic spike using hey or a busybox fallback loop.
set -euo pipefail

APP_URL="http://app.local"
DURATION=60   # seconds
QPS=50        # requests per second

echo "==> [Traffic] Starting traffic spike: ${QPS} RPS for ${DURATION}s"
echo "    Target: ${APP_URL}/users"
echo ""

if command -v hey &>/dev/null; then
  hey -z "${DURATION}s" -q "$QPS" -c 20 "${APP_URL}/users"
else
  echo "    'hey' not found — using busybox fallback via kubectl run..."
  kubectl run traffic-spike \
    --image=busybox \
    --restart=Never \
    --rm -it \
    --namespace=apps \
    -- /bin/sh -c "
      END=\$(( \$(date +%s) + ${DURATION} ))
      COUNT=0
      while [ \$(date +%s) -lt \$END ]; do
        wget -q -O /dev/null '${APP_URL}/users' 2>/dev/null || true
        COUNT=\$(( COUNT + 1 ))
        sleep 0.02
      done
      echo \"Sent \$COUNT requests\"
    "
fi

echo ""
echo "==> Chaos Scenario 4 complete."
echo "    Check Grafana for latency spike, then read docs/runbooks/04-traffic-spike.md."
