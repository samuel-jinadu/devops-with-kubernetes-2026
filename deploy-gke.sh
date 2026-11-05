#!/bin/bash
set -euo pipefail

# ─── 0. Deployment target ───────────────────────────────────────────────
# TARGET_NS:  staging | production | <feature-branch>
# TARGET_TAG: main | vX.Y.Z | <feature-branch>
#
#   main branch push   → staging / main       (Argo CD owns the workload)
#   tag push (v*..)    → production / <tag>   (Argo CD owns the workload)
#   feature branch     → <branch> / <branch>  (direct kubectl, ephemeral)
TARGET_NS="${TARGET_NS:-staging}"
TARGET_TAG="${TARGET_TAG:-main}"
BACKUP_BUCKET="${BACKUP_BUCKET:-todo-backups-$(gcloud config get-value project 2>/dev/null || echo dwk)}"

STORAGE_EMULATOR_HOST="${STORAGE_EMULATOR_HOST:-}"

# Guardrails
if ! [[ "$TARGET_NS" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]]; then
  echo "✖ Invalid namespace: '$TARGET_NS'"
  exit 1
fi
case "$TARGET_NS" in
  exercises|default|kube-system|kube-public|kube-node-lease|envoy-gateway-system|monitoring|argocd|argo-rollouts)
    echo "✖ Refusing to deploy into reserved namespace '$TARGET_NS'"
    exit 1
    ;;
esac

echo "▶ Target namespace: $TARGET_NS (image tag: $TARGET_TAG)"

# ─── Helper: emulator host detection ────────────────────────────────────
detect_emulator_host() {
  if [ -n "${STORAGE_EMULATOR_HOST}" ]; then
    local h="${STORAGE_EMULATOR_HOST#http://}"; h="${h#https://}"; h="${h%%:*}"
    echo "$h"; return
  fi
  if getent hosts host.docker.internal >/dev/null 2>&1; then echo "host.docker.internal"; return; fi
  local ip
  ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{if .IPAddress}}{{.IPAddress}} {{end}}{{end}}' floci-gcp 2>/dev/null | awk '{print $1}')
  if [ -n "$ip" ]; then echo "$ip"; return; fi
  echo "172.17.0.1"
}

# ─── Helper: apply a remote YAML with retries ───────────────────────────
# GitHub's release CDN occasionally 504s for a few seconds. Retry with
# exponential-ish backoff (5 attempts, ~4/7/12/19 s) before giving up.
apply_remote() {
  local url="$1"
  local desc="${2:-$url}"
  local attempt
  for attempt in 1 2 3 4 5; do
    if kubectl apply --request-timeout=90s -f "$url"; then
      return 0
    fi
    if [ "$attempt" -eq 5 ]; then
      echo "✖ apply_remote: giving up on ${desc} after 5 attempts"
      return 1
    fi
    local wait=$(( attempt * attempt + 3 ))
    echo "  ⚠  ${desc} attempt ${attempt}/5 failed — retrying in ${wait}s"
    sleep "${wait}"
  done
}

# ─── 1. Cluster ─────────────────────────────────────────────────────────
if ! gcloud container clusters describe dwk-cluster --zone=europe-north1-b >/dev/null 2>&1; then
  gcloud container clusters create dwk-cluster \
    --zone=europe-north1-b --num-nodes=2 --machine-type=e2-small --gateway-api=standard
else
  echo "▶ dwk-cluster already exists; skipping creation."
fi

echo "▶ waiting for cluster to be RUNNING…"
until [ "$(gcloud container clusters list --zone=europe-north1-b \
  --filter="name=dwk-cluster" --format="value(status)")" = "RUNNING" ]; do
  sleep 5
done

gcloud container clusters get-credentials dwk-cluster --zone=europe-north1-b

echo "▶ waiting for nodes to register..."
for i in $(seq 1 30); do
  kubectl get nodes 2>/dev/null | grep -q " Ready" && break
  sleep 2
done
kubectl wait --for=condition=Ready nodes --all --timeout=180s

# ─── 2. Namespaces ──────────────────────────────────────────────────────
kubectl apply -f manifests/namespaces
kubectl create namespace "$TARGET_NS" --dry-run=client -o yaml | kubectl apply -f -

# ─── 3. GatewayClass (real GKE vs emulator) ────────────────────────────
GATEWAY_CLASS=""
if kubectl get gatewayclass gke-l7-global-external-managed &>/dev/null; then
  echo "▶ Real GKE detected."
  GATEWAY_CLASS="gke-l7-global-external-managed"
else
  echo "▶ Emulator detected; installing Envoy Gateway..."

  apply_remote \
    "https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.0/standard-install.yaml" \
    "Gateway API standard-install CRDs"

  helm upgrade --install eg oci://docker.io/envoyproxy/gateway-helm \
    --version v1.5.4 --skip-crds -n envoy-gateway-system --create-namespace
  kubectl wait --for=condition=Available deployment/envoy-gateway -n envoy-gateway-system --timeout=300s

  kubectl apply -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
EOF
  kubectl wait --for=condition=Accepted gatewayclass/eg --timeout=120s
  GATEWAY_CLASS="eg"
fi

# ─── 3b. Knative Serving (for serverless ping-pong) ────────────────────
KNATIVE_VERSION="v1.21.3"
KOURIER_VERSION="v1.21.1"

# A real "is Knative installed" check — namespace alone isn't enough, since
# a CDN failure mid-apply leaves knative-serving in place but missing the
# actual Deployments.
knative_ready() {
  kubectl -n knative-serving get deployment/controller >/dev/null 2>&1 && \
  kubectl -n knative-serving get deployment/webhook    >/dev/null 2>&1 && \
  kubectl -n knative-serving get deployment/activator  >/dev/null 2>&1 && \
  kubectl -n knative-serving get deployment/autoscaler >/dev/null 2>&1 && \
  kubectl -n kourier-system  get deployment -l app=3scale-kourier-gateway >/dev/null 2>&1
}

if ! knative_ready; then
  echo "▶ Installing Knative Serving ${KNATIVE_VERSION} + Kourier ${KOURIER_VERSION}..."

  apply_remote \
    "https://github.com/knative/serving/releases/download/knative-${KNATIVE_VERSION}/serving-crds.yaml" \
    "Knative Serving CRDs"

  apply_remote \
    "https://github.com/knative/serving/releases/download/knative-${KNATIVE_VERSION}/serving-core.yaml" \
    "Knative Serving core"

  apply_remote \
    "https://github.com/knative-extensions/net-kourier/releases/download/knative-${KOURIER_VERSION}/kourier.yaml" \
    "Kourier"

  kubectl patch configmap/config-network \
    --namespace knative-serving --type merge \
    --patch '{"data":{"ingress-class":"kourier.ingress.networking.knative.dev"}}'

  # Magic DNS (sslip.io) — harmless on both emulator and real GKE
  apply_remote \
    "https://github.com/knative/serving/releases/download/knative-${KNATIVE_VERSION}/serving-default-domain.yaml" \
    "Knative magic DNS (serving-default-domain)"

  for d in controller webhook activator autoscaler; do
    kubectl -n knative-serving rollout status deployment/"$d" --timeout=300s
  done
  for d in $(kubectl -n kourier-system get deploy -o name); do
    kubectl -n kourier-system rollout status "$d" --timeout=300s
  done
  echo "✅ Knative ready"
else
  echo "▶ Knative already installed; skipping."
fi

# ─── 4. Gateway ─────────────────────────────────────────────────────────
sed "s|gatewayClassName: .*|gatewayClassName: ${GATEWAY_CLASS}|" \
  gke-manifests/gateway.yaml | kubectl apply -f -

# ─── 5. Secrets (applied OUTSIDE Argo CD) ──────────────────────────────
# postgres-credentials: staging AND production both need these
if [ "$TARGET_NS" = "staging" ] || [ "$TARGET_NS" = "production" ]; then
  sops --decrypt postgres/postgres-credentials.enc.yaml         | kubectl apply -f -
  sops --decrypt postgres/postgres-credentials-project.enc.yaml \
    | sed "s|namespace: project|namespace: ${TARGET_NS}|" \
    | kubectl apply -f -
fi

# Production-only secrets + config: broadcaster-webhook, storage-sa-key, backup-config
if [ "$TARGET_NS" = "production" ]; then
  sops --decrypt broadcaster/manifests/broadcaster-credentials.enc.yaml \
    | sed "s|namespace: project|namespace: production|" \
    | kubectl apply -f -

  if [ -f key.json ]; then
    kubectl create secret generic storage-sa-key \
      --from-file=key.json=key.json -n production \
      --dry-run=client -o yaml | kubectl apply -f -
  fi

  if [ "${GATEWAY_CLASS}" = "gke-l7-global-external-managed" ]; then
    if ! gsutil ls -b "gs://${BACKUP_BUCKET}" >/dev/null 2>&1; then
      echo "▶ Creating GCS bucket gs://${BACKUP_BUCKET}"
      gsutil mb -l europe-north1 "gs://${BACKUP_BUCKET}"
    fi
    kubectl -n production create configmap backup-config \
      --from-literal=BACKUP_BUCKET="${BACKUP_BUCKET}" \
      --dry-run=client -o yaml | kubectl apply -f -
  else
    if ! curl -fsS "http://localhost:4588/storage/v1/b/${BACKUP_BUCKET}" >/dev/null 2>&1; then
      curl -fsS -X POST "http://localhost:4588/storage/v1/b?project=floci-local" \
           -H "Content-Type: application/json" \
           -d "{\"name\": \"${BACKUP_BUCKET}\"}" >/dev/null 2>&1 || true
    fi
    EMULATOR_HOST=$(detect_emulator_host)
    kubectl -n production create configmap backup-config \
      --from-literal=BACKUP_BUCKET="${BACKUP_BUCKET}" \
      --from-literal=STORAGE_EMULATOR_HOST="http://${EMULATOR_HOST}:4588" \
      --dry-run=client -o yaml | kubectl apply -f -
  fi
fi

# ─── 6. Postgres (shared) ───────────────────────────────────────────────
kubectl apply -f postgres/postgres.yaml
echo "▶ waiting for Postgres…"
kubectl -n exercises rollout status statefulset/postgres-stset --timeout=180s

# ─── 7. Monitoring + Argo Rollouts ─────────────────────────────────────
echo "▶ Installing/upgrading Prometheus stack..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  -f helm/monitoring-values.yaml --wait --timeout 10m

echo "✅ Monitoring stack ready."

kubectl create namespace argo-rollouts --dry-run=client -o yaml | kubectl apply -f -
kubectl apply --server-side --force-conflicts \
  -n argo-rollouts \
  -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
kubectl apply -f gke-manifests/argo-rollouts-gatewayapi-rbac.yaml

ARCH=$(uname -m); case "$ARCH" in x86_64) PLUGIN_ARCH="amd64" ;; aarch64|arm64) PLUGIN_ARCH="arm64" ;; esac
PLUGIN_URL="https://github.com/argoproj-labs/rollouts-plugin-trafficrouter-gatewayapi/releases/download/v0.4.0/gatewayapi-plugin-linux-${PLUGIN_ARCH}"
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: argo-rollouts-config
  namespace: argo-rollouts
data:
  trafficRouterPlugins: |-
    - name: "argoproj-labs/gatewayAPI"
      location: "${PLUGIN_URL}"
EOF
kubectl -n argo-rollouts rollout restart deployment argo-rollouts
kubectl -n argo-rollouts rollout status deployment/argo-rollouts --timeout=180s

# ─── 7b. Ping-pong as a Knative Service ────────────────────────────────
echo "▶ Deploying ping-pong as a Knative Service..."
kubectl apply -f ping-pong/knative-service.yaml
kubectl -n exercises wait --for=condition=Ready ksvc/pingpong --timeout=300s

PINGPONG_HOST=$(
  kubectl -n exercises get ksvc pingpong -o jsonpath='{.status.url}' \
    | sed -E 's#^https?://##'
)
[ -z "$PINGPONG_HOST" ] && PINGPONG_HOST="pingpong.exercises.svc.cluster.local"
echo "▶ /pingpong will rewrite Host → ${PINGPONG_HOST}"

# Bridge Service: gives Envoy Gateway a Service-with-EndpointSlices fronting
# the same pods. The ksvc-level Service "pingpong" is managed by Kourier via
# the deprecated v1.Endpoints kind, which Envoy Gateway does not read.
echo "▶ Applying pingpong-gw bridge Service..."
kubectl apply -f ping-pong/gke-manifests/pingpong-bridge-svc.yaml

echo "▶ Waiting for pingpong-gw to get endpoints..."
for i in $(seq 1 30); do
  if kubectl -n exercises get endpointslices \
       -l kubernetes.io/service-name=pingpong-gw \
       -o json 2>/dev/null | grep -q '"addresses"'; then
    echo "  ✅ pingpong-gw has endpoints"
    break
  fi
  sleep 1
  if [ "$i" -eq 30 ]; then
    echo "  ⚠  pingpong-gw has no endpoints yet (pod may not be Ready); continuing"
  fi
done

echo "▶ Applying /pingpong HTTPRoute → pingpong-gw…"
sed "s|__PINGPONG_HOST__|${PINGPONG_HOST}|g" \
  ping-pong/gke-manifests/httproute.yaml | kubectl apply -f -

# ─── 7c. NATS ───────────────────────────────────────────────────────────
echo "▶ Installing/upgrading NATS..."
helm repo add nats https://nats-io.github.io/k8s/helm/charts/ >/dev/null 2>&1 || true
helm repo update nats >/dev/null
helm upgrade --install nats nats/nats --namespace exercises --create-namespace \
  --set config.jetstream.enabled=false --wait --timeout 5m
kubectl -n exercises rollout status statefulset/nats --timeout=180s

# ─── 7d. Argo CD ────────────────────────────────────────────────────────
echo "▶ Installing/upgrading Argo CD..."
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update argo >/dev/null
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  --set controller.replicas=1 --set server.replicas=1 \
  --set repoServer.replicas=1 --set applicationSet.replicas=0 \
  --set notifications.enabled=false --set dex.enabled=false \
  --wait --timeout 10m
kubectl -n argocd rollout status deployment/argocd-server --timeout=300s
kubectl -n argocd rollout status deployment/argocd-repo-server --timeout=300s

# CronJob health override (CronJobs report Progressing forever otherwise)
kubectl -n argocd patch configmap argocd-cm --type merge --patch '
data:
  resource.customizations.health.batch_CronJob: |
    hs = {}
    hs.status = "Healthy"
    hs.message = "CronJob schedule is configured; job execution is verified separately"
    return hs
'
sleep 3

# ─── 8. Direct deploy (branches, or when FORCE_DIRECT_APPLY=1) ─────────
should_direct_apply=0
if [ "${FORCE_DIRECT_APPLY:-0}" = "1" ]; then
  should_direct_apply=1
elif [ "$TARGET_NS" != "staging" ] && [ "$TARGET_NS" != "production" ]; then
  should_direct_apply=1
fi

if [ "$should_direct_apply" = "0" ]; then
  echo "▶ $TARGET_NS is managed by Argo CD — skipping direct apply (see §9)."
elif [ "$TARGET_NS" = "staging" ] || [ "$TARGET_NS" = "production" ]; then
  echo "▶ FORCE_DIRECT_APPLY=1 — applying gitops/$TARGET_NS directly into $TARGET_NS"
  kubectl apply -k "gitops/$TARGET_NS"
  kubectl -n "$TARGET_NS" rollout status deployment/todo-backend-deployment --timeout=120s
  kubectl -n "$TARGET_NS" rollout status deployment/todo-app-deployment     --timeout=120s
  kubectl -n "$TARGET_NS" rollout status deployment/broadcaster             --timeout=180s
else
  echo "▶ Branch deploy: applying gitops/base/ directly into $TARGET_NS"
  APP_TMP=$(mktemp -d)
  cp -r gitops/base/todo-backend "$APP_TMP/"
  cp -r gitops/base/todo-app     "$APP_TMP/"

  cat > "$APP_TMP/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ${TARGET_NS}
images:
  - name: ghcr.io/samuel-jinadu/todo-backend
    newTag: ${TARGET_TAG}
  - name: ghcr.io/samuel-jinadu/todo-app
    newTag: ${TARGET_TAG}
resources:
  - ./todo-backend
  - ./todo-app
EOF

  kubectl apply -k "$APP_TMP"
  rm -rf "$APP_TMP"

  sed -e "s|namespace: project|namespace: ${TARGET_NS}|" \
      -e "s|image: ghcr.io/samuel-jinadu/broadcaster:main|image: ghcr.io/samuel-jinadu/broadcaster:${TARGET_TAG}|" \
      gitops/base/broadcaster/deployment.yaml | kubectl apply -f -
  sed "s|namespace: project|namespace: ${TARGET_NS}|" \
      gitops/base/cronjobs/gen-todo-hourly.yaml | kubectl apply -f -

  kubectl -n "$TARGET_NS" rollout status deployment/todo-backend-deployment --timeout=120s
  kubectl -n "$TARGET_NS" rollout status deployment/todo-app-deployment     --timeout=120s
  kubectl -n "$TARGET_NS" rollout status deployment/broadcaster             --timeout=180s
fi

# ─── 9. Argo CD Applications ───────────────────────────────────────────
GITOPS_REPO_URL="${GITOPS_REPO_URL:-}"
GITOPS_REVISION="${GITOPS_REVISION:-main}"
if [ -z "${GITOPS_REPO_URL}" ]; then
  if [ -n "${GITHUB_REPOSITORY:-}" ]; then
    GITOPS_REPO_URL="https://github.com/${GITHUB_REPOSITORY}.git"
  else
    GITOPS_REPO_URL="https://github.com/samuel-jinadu/devops-with-kubernetes-2026.git"
  fi
fi

if [ "${FORCE_DIRECT_APPLY:-0}" = "1" ]; then
  echo "▶ FORCE_DIRECT_APPLY=1 — skipping Argo CD Application updates"
else
  kubectl -n argocd delete application project --ignore-not-found 2>/dev/null || true

  echo "▶ Application log-output (rev=${GITOPS_REVISION})"
  sed -e "s|__GITOPS_REPO_URL__|${GITOPS_REPO_URL}|g" \
      -e "s|__GITOPS_REVISION__|${GITOPS_REVISION}|g" \
      argocd/log-output-app.yaml | kubectl apply -f -

  echo "▶ Application project-staging (tracks main)"
  sed "s|__GITOPS_REPO_URL__|${GITOPS_REPO_URL}|g" \
      argocd/staging-app.yaml | kubectl apply -f -

  if [ "$TARGET_NS" = "production" ] && [ "$TARGET_TAG" != "main" ]; then
    echo "▶ Application project-production (tracks tag ${TARGET_TAG})"
    sed -e "s|__GITOPS_REPO_URL__|${GITOPS_REPO_URL}|g" \
        -e "s|__PRODUCTION_TAG__|${TARGET_TAG}|g" \
        argocd/production-app.yaml | kubectl apply -f -
  elif ! kubectl -n argocd get application project-production >/dev/null 2>&1; then
    echo "▶ production Application not yet created (will be created on first tag push)"
  fi

  APPS_TO_WAIT="log-output project-staging"
  if kubectl -n argocd get application project-production >/dev/null 2>&1; then
    APPS_TO_WAIT="$APPS_TO_WAIT project-production"
  fi

  echo "▶ waiting for Argo CD to converge: $APPS_TO_WAIT"
  for app in $APPS_TO_WAIT; do
    for i in $(seq 1 60); do
      synced=$(kubectl -n argocd get application "$app" -o jsonpath='{.status.sync.status}'   2>/dev/null || true)
      health=$(kubectl -n argocd get application "$app" -o jsonpath='{.status.health.status}' 2>/dev/null || true)
      if [ "$synced" = "Synced" ] && [ "$health" = "Healthy" ]; then
        echo "  ✅ $app: ${synced}/${health}"
        break
      fi
      echo "  $app: ${synced:-Pending}/${health:-Pending} (attempt $i/60)"
      sleep 5
      if [ "$i" -eq 60 ]; then
        echo "✖ $app did not converge. Dumping status:"
        kubectl -n argocd get application "$app" -o yaml | tail -80
        exit 1
      fi
    done
  done
fi

# ─── 10. Wait for Gateway data plane ───────────────────────────────────
GATEWAY_NAME="exercises-gateway"; NS="exercises"

if [ "${GATEWAY_CLASS}" = "gke-l7-global-external-managed" ]; then
  echo "▶ Waiting for Gateway Programmed (real GKE)..."
  kubectl wait --for=condition=Programmed gateway/"${GATEWAY_NAME}" -n "${NS}" --timeout=600s
else
  echo "▶ Waiting for Envoy data plane (emulator)..."
  ENVOY_SVC=""; ENVOY_DEPLOY=""
  for i in $(seq 1 90); do
    ENVOY_SVC=$(kubectl get svc -n envoy-gateway-system \
      --selector=gateway.envoyproxy.io/owning-gateway-namespace=${NS},gateway.envoyproxy.io/owning-gateway-name=${GATEWAY_NAME} \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    ENVOY_DEPLOY=$(kubectl get deploy -n envoy-gateway-system \
      --selector=gateway.envoyproxy.io/owning-gateway-namespace=${NS},gateway.envoyproxy.io/owning-gateway-name=${GATEWAY_NAME} \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    if [ -n "${ENVOY_SVC}" ] && [ -n "${ENVOY_DEPLOY}" ]; then
      kubectl -n envoy-gateway-system rollout status deploy/"${ENVOY_DEPLOY}" --timeout=120s
      break
    fi
    sleep 2
    [ "$i" -eq 90 ] && { echo "✖ Envoy data plane timed out"; exit 1; }
  done
fi

# ─── 11. Gateway address + port-forward (emulator) ────────────────────
GATEWAY_ADDRESS=""; PORT_FORWARD_PID=""

if [ "${GATEWAY_CLASS}" = "gke-l7-global-external-managed" ]; then
  GATEWAY_ADDRESS=$(kubectl get gateway/"${GATEWAY_NAME}" -n "${NS}" -o jsonpath='{.status.addresses[0].value}')
  [ -z "${GATEWAY_ADDRESS}" ] && { echo "✖ Gateway address empty"; exit 1; }
else
  [ -z "${ENVOY_SVC:-}" ] && ENVOY_SVC=$(kubectl get svc -n envoy-gateway-system \
    --selector=gateway.envoyproxy.io/owning-gateway-namespace=${NS},gateway.envoyproxy.io/owning-gateway-name=${GATEWAY_NAME} \
    -o jsonpath='{.items[0].metadata.name}')
  [ -z "${ENVOY_SVC}" ] && { echo "✖ Envoy service not found"; exit 1; }

  PORT_FORWARD_PORT="${PORT_FORWARD_PORT:-8060}"
  pkill -f "kubectl.*port-forward.*${PORT_FORWARD_PORT}" 2>/dev/null || true
  sleep 1
  kubectl -n envoy-gateway-system port-forward svc/"${ENVOY_SVC}" ${PORT_FORWARD_PORT}:80 \
    >/tmp/envoy-port-forward.log 2>&1 &
  PORT_FORWARD_PID=$!
  sleep 2
  kill -0 "${PORT_FORWARD_PID}" 2>/dev/null || { echo "✖ Port-forward died"; exit 1; }
  GATEWAY_ADDRESS="localhost:${PORT_FORWARD_PORT}"
fi

# ─── 12. URLs ──────────────────────────────────────────────────────────
echo ""
echo "✅ Gateway address: ${GATEWAY_ADDRESS}"
echo "   Target namespace: ${TARGET_NS}  (image tag: ${TARGET_TAG})"
echo "   Ping-pong:   http://${GATEWAY_ADDRESS}/pingpong"
echo "   Log-output:  http://${GATEWAY_ADDRESS}/log"
if [ "$TARGET_NS" = "production" ]; then
  echo "   Todo app:    http://${GATEWAY_ADDRESS}/"
  echo "   Todo submit: http://${GATEWAY_ADDRESS}/submit"
  echo "   Todo list:   http://${GATEWAY_ADDRESS}/backend"
else
  echo "   Staging todo-app is internal-only. To reach it:"
  echo "     kubectl -n staging port-forward svc/todo-app-service-cluster-ip 8080:2345"
  echo "     then open http://localhost:8080/"
fi
[ -n "${PORT_FORWARD_PID}" ] && echo "ℹ️  Port-forward PID ${PORT_FORWARD_PID} (kill ${PORT_FORWARD_PID} to stop)"
echo ""