#!/usr/bin/env bash
# Scenario 1: Force an OOM kill by requesting 300 MB on a pod limited to 256 Mi.
set -euo pipefail

APP_URL="http://app.local"
APP_NS=apps

echo "==> [OOM] Checking current pod state..."
kubectl get pods -n "$APP_NS" -l app=dummy-webapp

echo ""
echo "==> [OOM] Sending stress request (300 MB allocation, limit is 256 Mi)..."
echo "    This will cause the pod to be OOMKilled within ~10 seconds."
echo ""

curl -sf --max-time 5 "${APP_URL}/stress?mb=300" || true

echo ""
echo "==> [OOM] Waiting 15s for OOMKill event..."
sleep 15

echo ""
echo "==> [OOM] Current pod state (look for OOMKilled in LAST_STATE):"
kubectl get pods -n "$APP_NS" -l app=dummy-webapp
echo ""
echo "==> [OOM] Describe output:"
kubectl describe pod -n "$APP_NS" -l app=dummy-webapp | grep -A 20 "Last State:"

echo ""
echo "==> Chaos Scenario 1 complete."
echo "    Read docs/runbooks/01-oom-kill.md to resolve."
