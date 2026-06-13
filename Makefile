.PHONY: init deploy-infra deploy-apps hosts open status destroy reset-app \
        chaos-oom chaos-rundeck chaos-nginx chaos-traffic chaos-db break-things \
        fix-oom fix-rundeck fix-nginx fix-traffic fix-db fix-all \
        _wait-for-pods

MINIKUBE_CPUS     := 4
MINIKUBE_MEMORY   := 8192
MINIKUBE_DISK     := 30g
MINIKUBE_DRIVER   := docker

CLUSTER_NAMESPACE_MONITORING := monitoring
CLUSTER_NAMESPACE_ARGOCD     := argocd
CLUSTER_NAMESPACE_RUNDECK    := rundeck
CLUSTER_NAMESPACE_GITEA      := gitea
CLUSTER_NAMESPACE_APPS       := apps

APP_IMAGE         := dummy-webapp:latest
GITEA_USER        := gitadmin
GITEA_PASS        := password
GITEA_REPO        := mcp-demo
ARGOCD_PASS       := password

ANSIBLE           := ansible-playbook -i ansible/inventory/localhost.ini

# ─── CLUSTER SETUP ───────────────────────────────────────────────────────────

init:
	@echo "==> Starting Minikube..."
	bash scripts/start-minikube.sh
	@echo "==> Adding Helm repos..."
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo add argo                 https://argoproj.github.io/argo-helm
	helm repo add rundeck              https://rundeck.github.io/helm-charts
	helm repo add gitea-charts         https://dl.gitea.com/charts/
	helm repo update
	@echo "==> Creating namespaces..."
	kubectl create namespace $(CLUSTER_NAMESPACE_MONITORING) --dry-run=client -o yaml | kubectl apply -f -
	kubectl create namespace $(CLUSTER_NAMESPACE_ARGOCD)     --dry-run=client -o yaml | kubectl apply -f -
	kubectl create namespace $(CLUSTER_NAMESPACE_RUNDECK)    --dry-run=client -o yaml | kubectl apply -f -
	kubectl create namespace $(CLUSTER_NAMESPACE_GITEA)      --dry-run=client -o yaml | kubectl apply -f -
	kubectl create namespace $(CLUSTER_NAMESPACE_APPS)       --dry-run=client -o yaml | kubectl apply -f -
	@echo "==> Init complete."

deploy-infra: _deploy-prometheus _deploy-argocd _deploy-rundeck _deploy-gitea
	@echo "==> All infrastructure deployed."

_deploy-prometheus:
	@echo "==> Deploying kube-prometheus-stack..."
	helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
	  --namespace $(CLUSTER_NAMESPACE_MONITORING) \
	  --values helm/prometheus/values.yaml \
	  --wait --timeout 10m

_deploy-argocd:
	@echo "==> Deploying ArgoCD..."
	helm upgrade --install argocd argo/argo-cd \
	  --namespace $(CLUSTER_NAMESPACE_ARGOCD) \
	  --values helm/argocd/values.yaml \
	  --wait --timeout 8m
	@echo "==> Setting ArgoCD admin password..."
	bash scripts/setup-argocd.sh

_deploy-rundeck:
	@echo "==> Deploying Rundeck..."
	helm upgrade --install rundeck rundeck/rundeck \
	  --namespace $(CLUSTER_NAMESPACE_RUNDECK) \
	  --values helm/rundeck/values.yaml \
	  --wait --timeout 10m
	@echo "==> Loading Rundeck jobs..."
	bash scripts/setup-rundeck.sh

_deploy-gitea:
	@echo "==> Deploying Gitea..."
	helm upgrade --install gitea gitea-charts/gitea \
	  --namespace $(CLUSTER_NAMESPACE_GITEA) \
	  --values helm/gitea/values.yaml \
	  --wait --timeout 8m

# ─── APP DEPLOYMENT ──────────────────────────────────────────────────────────

deploy-apps:
	@echo "==> Building dummy-webapp image inside Minikube..."
	eval $$(minikube docker-env) && \
	  docker build -t $(APP_IMAGE) apps/dummy-webapp/
	@echo "==> Pushing k8s manifests to Gitea and configuring ArgoCD..."
	bash scripts/push-to-gitea.sh
	@echo "==> Creating ArgoCD Application..."
	kubectl apply -f argocd/apps/dummy-webapp-app.yaml
	@echo "==> Waiting for ArgoCD sync..."
	argocd app wait dummy-webapp --sync --health --timeout 120 2>/dev/null || true
	@echo "==> dummy-webapp deployed."

# ─── UTILITIES ───────────────────────────────────────────────────────────────

hosts:
	$(eval MINIKUBE_IP := $(shell minikube ip))
	@echo ""
	@echo "Add the following line to /etc/hosts (requires sudo):"
	@echo ""
	@echo "  $(MINIKUBE_IP)  grafana.local argocd.local rundeck.local gitea.local app.local"
	@echo ""
	@echo "Run:  sudo bash -c 'echo \"$(MINIKUBE_IP) grafana.local argocd.local rundeck.local gitea.local app.local\" >> /etc/hosts'"

open:
	@minikube service -n $(CLUSTER_NAMESPACE_MONITORING) kube-prometheus-stack-grafana --url | xargs open || true
	@minikube service -n $(CLUSTER_NAMESPACE_ARGOCD) argocd-server --url | head -1 | xargs open || true
	@minikube service -n $(CLUSTER_NAMESPACE_RUNDECK) rundeck --url | xargs open || true

status:
	@echo "=== PODS ==="
	kubectl get pods -A --sort-by=.metadata.namespace
	@echo ""
	@echo "=== ARGOCD APPS ==="
	kubectl get applications -n $(CLUSTER_NAMESPACE_ARGOCD) 2>/dev/null || echo "(ArgoCD not deployed)"
	@echo ""
	@echo "=== INGRESSES ==="
	kubectl get ingress -A

reset-app:
	kubectl delete -f argocd/apps/dummy-webapp-app.yaml --ignore-not-found
	kubectl delete namespace $(CLUSTER_NAMESPACE_APPS) --ignore-not-found
	kubectl create namespace $(CLUSTER_NAMESPACE_APPS)
	kubectl apply -f argocd/apps/dummy-webapp-app.yaml

_wait-for-pods:
	@echo "==> Waiting for all pods in $(NS) to be Ready..."
	kubectl wait --for=condition=Ready pods --all -n $(NS) --timeout=120s

destroy:
	@echo "==> Destroying Minikube cluster..."
	minikube delete
	@echo "==> Done."

# ─── CHAOS SCENARIOS ─────────────────────────────────────────────────────────

chaos-oom:
	@echo "==> [Scenario 1] Triggering OOM kill on dummy-webapp..."
	bash scripts/chaos/oom-kill.sh

chaos-rundeck:
	@echo "==> [Scenario 2] Triggering Rundeck chaos job..."
	bash scripts/chaos/rundeck-chaos.sh

chaos-nginx:
	@echo "==> [Scenario 3] Applying nginx IP whitelist block..."
	bash scripts/chaos/nginx-whitelist.sh

chaos-traffic:
	@echo "==> [Scenario 4] Starting traffic spike..."
	bash scripts/chaos/traffic-spike.sh

chaos-db:
	@echo "==> [Scenario 5] Corrupting SQLite database..."
	bash scripts/chaos/db-corruption.sh

break-things: chaos-oom
	@sleep 30
	$(MAKE) chaos-rundeck
	@sleep 10
	$(MAKE) chaos-nginx
	@sleep 10
	$(MAKE) chaos-traffic
	@sleep 10
	$(MAKE) chaos-db

# ─── FIX PLAYBOOKS ───────────────────────────────────────────────────────────

fix-oom:
	@echo "==> [Fix 1] Running OOM fix playbook..."
	$(ANSIBLE) ansible/playbooks/fix-oom.yaml

fix-rundeck:
	@echo "==> [Fix 2] Running Rundeck chaos fix playbook..."
	$(ANSIBLE) ansible/playbooks/fix-rundeck-chaos.yaml

fix-nginx:
	@echo "==> [Fix 3] Running nginx whitelist fix playbook..."
	$(ANSIBLE) ansible/playbooks/fix-nginx-whitelist.yaml

fix-traffic:
	@echo "==> [Fix 4] Running traffic spike fix playbook..."
	$(ANSIBLE) ansible/playbooks/fix-traffic-spike.yaml

fix-db:
	@echo "==> [Fix 5] Running DB corruption fix playbook..."
	$(ANSIBLE) ansible/playbooks/fix-db-corruption.yaml

fix-all: fix-oom fix-rundeck fix-nginx fix-traffic fix-db
	@echo "==> All fix playbooks complete."
