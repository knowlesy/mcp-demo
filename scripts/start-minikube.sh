#!/usr/bin/env bash
set -euo pipefail

CPUS=4
MEMORY=8192
DISK=30g
DRIVER=docker

echo "==> Checking prerequisites..."
for cmd in minikube kubectl helm docker; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: '$cmd' not found. Install it and re-run." >&2
    exit 1
  fi
done

if minikube status &>/dev/null; then
  echo "==> Minikube already running. Skipping start."
else
  echo "==> Starting Minikube (CPUs=$CPUS, Memory=${MEMORY}MB, Disk=$DISK, Driver=$DRIVER)..."
  minikube start \
    --cpus="$CPUS" \
    --memory="$MEMORY" \
    --disk-size="$DISK" \
    --driver="$DRIVER" \
    --kubernetes-version=stable \
    --extra-config=kubelet.housekeeping-interval=10s \
    --extra-config=controller-manager.bind-address=0.0.0.0 \
    --extra-config=scheduler.bind-address=0.0.0.0
fi

echo "==> Enabling addons..."
minikube addons enable ingress
minikube addons enable ingress-dns
minikube addons enable metrics-server
minikube addons enable registry 2>/dev/null || true

echo "==> Waiting for ingress controller to be ready..."
kubectl wait --namespace ingress-nginx \
  --for=condition=Ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

echo ""
echo "==> Minikube is ready."
echo "    IP: $(minikube ip)"
echo ""
echo "    Add to /etc/hosts:"
echo "    $(minikube ip)  grafana.local argocd.local rundeck.local gitea.local app.local"
