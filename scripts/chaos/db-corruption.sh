#!/usr/bin/env bash
# Scenario 5: Drop the 'users' table inside the running dummy-webapp pod.
set -euo pipefail

APP_NS=apps
APP_URL="http://app.local"

echo "==> [DB Corruption] Finding dummy-webapp pod..."
POD=$(kubectl get pod -n "$APP_NS" -l app=dummy-webapp -o jsonpath='{.items[0].metadata.name}')
echo "    Pod: $POD"

echo ""
echo "==> [DB Corruption] Baseline health check (expect 200):"
curl -sf -o /dev/null -w "HTTP Status: %{http_code}\n" "${APP_URL}/health" || echo "HTTP Status: error"

echo ""
echo "==> [DB Corruption] Dropping 'users' table via kubectl exec..."
kubectl exec -n "$APP_NS" "$POD" -- \
  python3 -c "
import sqlite3, os
db = os.environ.get('DB_PATH', '/data/app.db')
conn = sqlite3.connect(db)
conn.execute('DROP TABLE IF EXISTS users')
conn.execute('DROP TABLE IF EXISTS events')
conn.commit()
conn.close()
print('Tables dropped: users, events')
"

echo ""
echo "==> [DB Corruption] Post-corruption health check (expect 500):"
sleep 2
curl -sf -o /dev/null -w "HTTP Status: %{http_code}\n" "${APP_URL}/health" || \
  echo "HTTP Status: 500 (DB table missing — corruption confirmed)"

echo ""
echo "==> [DB Corruption] /users endpoint (expect 500 with error):"
curl -sf "${APP_URL}/users" 2>/dev/null || echo "Request failed — /users is broken"

echo ""
echo "==> Chaos Scenario 5 complete."
echo "    Read docs/runbooks/05-db-corruption.md to resolve."
