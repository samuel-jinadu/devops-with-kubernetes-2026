#!/bin/bash
set -euo pipefail

# ─── 0. Deployment target ─────────────────────────────────────────────────────
# TARGET_NS:  namespace for the project app (defaults to "project" = main)
# TARGET_TAG: image tag for todo-backend/todo-app (defaults to "main")
TARGET_NS="${TARGET_NS:-project}"
TARGET_TAG="${TARGET_TAG:-main}"

# Guardrails — reject obvious mistakes early
if ! [[ "$TARGET_NS" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]]; then
  echo "❌ Invalid namespace: '$TARGET_NS' (must match ^[a-z0-9]([-a-z0-9]*[a-z0-9])?\$)"
  exit 1
fi
case "$TARGET_NS" in
  exercises|default|kube-system|kube-public|kube-node-lease|envoy-gateway-system|monitoring)
    echo "❌ Refusing to deploy into reserved namespace '$TARGET_NS'"
    exit 1
    ;;
esac

echo "▶ Target namespace: $TARGET_NS (image tag: $TARGET_TAG)"

# ─── 1. Cluster ───────────────────────────────────────────────────────────────
if ! gcloud container clusters describe dwk-cluster --zone=europe-north1-b >/dev/null 2>&1; then
  gcloud container clusters create dwk-cluster \
    --zone=europe-north1-b \
    --num-nodes=2 \
    --machine-type=e2-small \
    --gateway-api=standard
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
  if kubectl get nodes 2>/dev/null | grep -q " Ready"; then
    break
  fi
  sleep 2
done
kubectl wait --for=condition=Ready nodes --all --timeout=180s

# ─── 2. Namespaces ────────────────────────────────────────────────────────────
kubectl apply -f manifests/namespaces   # creates exercises + project
# Create the branch namespace if deploying somewhere other than project
kubectl create namespace "$TARGET_NS" --dry-run=client -o yaml | kubectl apply -f -

# ─── 3. Decide which GatewayClass to use (real GKE vs emulator) ───────────────
GATEWAY_CLASS=""
if kubectl get gatewayclass gke-l7-global-external-managed &>/dev/null; then
  echo "▶ Real GKE detected; using GKE-managed GatewayClass."
  GATEWAY_CLASS="gke-l7-global-external-managed"
else
  echo "▶ GKE GatewayClass not found; assuming emulator; installing Envoy Gateway..."

  kubectl apply --server-side -f \
    https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.0/standard-install.yaml

  helm upgrade --install eg oci://docker.io/envoyproxy/gateway-helm \
    --version v1.5.4 \
    --skip-crds \
    -n envoy-gateway-system --create-namespace

  kubectl wait --for=condition=Available deployment/envoy-gateway \
    -n envoy-gateway-system --timeout=300s

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

# ─── 4. Gateway (patched on the fly) ──────────────────────────────────────────
sed "s|gatewayClassName: .*|gatewayClassName: ${GATEWAY_CLASS}|" \
  gke-manifests/gateway.yaml | kubectl apply -f -

# ─── 5. Secrets (decrypted from sops) ─────────────────────────────────────────
sops --decrypt postgres/postgres-credentials.enc.yaml         | kubectl apply -f -
sops --decrypt postgres/postgres-credentials-project.enc.yaml \
  | sed "s|namespace: project|namespace: ${TARGET_NS}|" \
  | kubectl apply -f -

# ─── 6. Postgres (shared, always in exercises) ────────────────────────────────
kubectl apply -f postgres/postgres.yaml
echo "▶ waiting for Postgres…"
kubectl -n exercises rollout status statefulset/postgres-stset --timeout=180s

# ─── 7. Shared infra (exercises namespace) ────────────────────────────────────
kubectl apply -f ping-pong/gke-manifests
echo "▶ waiting for ping-pong…"
kubectl -n exercises rollout status deployment/pingpong-dep --timeout=120s

kubectl apply -f log-output/gke-manifests
echo "▶ waiting for log-output…"
kubectl -n exercises rollout status deployment/hashgenerator-dep --timeout=120s

# ─── 8. Project app → TARGET_NS with TARGET_TAG and per-branch URL prefixes ───
APP_TMP=$(mktemp -d)

# Copy manifests INTO the temp dir so all resources are relative to it
# (kustomize refuses absolute paths in `resources:`)
cp -r todo-backend/manifests "$APP_TMP/todo-backend-manifests"
cp -r todo-app/manifests     "$APP_TMP/todo-app-manifests"

{
  cat <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ${TARGET_NS}
images:
  - name: ghcr.io/samuel-jinadu/todo-backend
    newTag: ${TARGET_TAG}
  - name: ghcr.io/samuel-jinadu/todo-app
    newTag: ${TARGET_TAG}
resources:
  - ./todo-backend-manifests
  - ./todo-app-manifests
EOF

  # Branch-only patches: prefix HTTPRoute paths with /<ns>/ and rewrite
  # internally so the Go handlers stay unchanged. Main keeps the root paths.
  if [ "$TARGET_NS" != "project" ]; then
    cat <<EOF
patches:
  - target: { kind: HTTPRoute, name: todo-backend-route }
    patch: |-
      - op: replace
        path: /spec/rules/0/matches/0/path/value
        value: /${TARGET_NS}/submit
      - op: replace
        path: /spec/rules/1/matches/0/path/value
        value: /${TARGET_NS}/backend
      - op: add
        path: /spec/rules/0/filters
        value:
          - type: URLRewrite
            urlRewrite:
              path: { type: ReplacePrefixMatch, replacePrefixMatch: /submit }
      - op: add
        path: /spec/rules/1/filters
        value:
          - type: URLRewrite
            urlRewrite:
              path: { type: ReplacePrefixMatch, replacePrefixMatch: /backend }
  - target: { kind: HTTPRoute, name: todo-app-route }
    patch: |-
      - op: replace
        path: /spec/rules/0/matches/0/path/value
        value: /${TARGET_NS}/
      - op: add
        path: /spec/rules/0/filters
        value:
          - type: URLRewrite
            urlRewrite:
              path: { type: ReplacePrefixMatch, replacePrefixMatch: / }
  - target: { kind: ConfigMap, name: todo-app-configmap }
    patch: |-
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: todo-app-configmap
      data:
        POSTURL: /${TARGET_NS}/submit
  - target: { kind: Deployment, name: todo-backend-deployment }
    patch: |-
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: todo-backend-deployment
      spec:
        template:
          spec:
            containers:
              - name: todo-backend
                env:
                  - name: TODOAPP_ROUTE
                    value: /${TARGET_NS}/
EOF
  fi
} > "$APP_TMP/kustomization.yaml"

kubectl apply -k "$APP_TMP"
rm -rf "$APP_TMP"

echo "▶ waiting for todo-backend in $TARGET_NS…"
kubectl -n "$TARGET_NS" rollout status deployment/todo-backend-deployment --timeout=120s
echo "▶ waiting for todo-app in $TARGET_NS…"
kubectl -n "$TARGET_NS" rollout status deployment/todo-app-deployment --timeout=120s

# ─── 9. CronJob → TARGET_NS ───────────────────────────────────────────────────
sed "s|namespace: project|namespace: ${TARGET_NS}|" \
  manifests/cronjobs/gen-todo-hourly.yaml | kubectl apply -f -

# ─── 10. GKE-only: health check for ping-pong LB ──────────────────────────────
if [ "${GATEWAY_CLASS}" = "gke-l7-global-external-managed" ]; then
  echo "▶ Applying GKE HealthCheckPolicy…"
  kubectl apply -f gke-manifests/pingpong-healthcheckpolicy.yaml
fi

# ─── 11. Wait for the Gateway data plane ──────────────────────────────────────
GATEWAY_NAME="exercises-gateway"
NS="exercises"

if [ "${GATEWAY_CLASS}" = "gke-l7-global-external-managed" ]; then
  echo "▶ Waiting for Gateway to be Programmed (real GKE)..."
  kubectl wait --for=condition=Programmed gateway/"${GATEWAY_NAME}" \
    -n "${NS}" --timeout=600s
else
  echo "▶ Waiting for Envoy data plane to appear (emulator)..."
  ENVOY_SVC=""
  ENVOY_DEPLOY=""
  for i in $(seq 1 90); do
    ENVOY_SVC=$(kubectl get svc -n envoy-gateway-system \
      --selector=gateway.envoyproxy.io/owning-gateway-namespace=${NS},gateway.envoyproxy.io/owning-gateway-name=${GATEWAY_NAME} \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

    ENVOY_DEPLOY=$(kubectl get deploy -n envoy-gateway-system \
      --selector=gateway.envoyproxy.io/owning-gateway-namespace=${NS},gateway.envoyproxy.io/owning-gateway-name=${GATEWAY_NAME} \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

    if [ -n "${ENVOY_SVC}" ] && [ -n "${ENVOY_DEPLOY}" ]; then
      echo "  Found Envoy service=${ENVOY_SVC} deployment=${ENVOY_DEPLOY}"
      kubectl -n envoy-gateway-system rollout status \
        deploy/"${ENVOY_DEPLOY}" --timeout=120s
      break
    fi
    sleep 2
    if [ "$i" -eq 90 ]; then
      echo "❌ Timed out waiting for Envoy data plane."
      echo "   Hint: kubectl get svc,deploy -n envoy-gateway-system"
      echo "         kubectl describe gateway ${GATEWAY_NAME} -n ${NS}"
      exit 1
    fi
  done
fi

# ─── 12. Resolve the Gateway address ──────────────────────────────────────────
GATEWAY_ADDRESS=""
PORT_FORWARD_PID=""

if [ "${GATEWAY_CLASS}" = "gke-l7-global-external-managed" ]; then
  GATEWAY_ADDRESS=$(kubectl get gateway/"${GATEWAY_NAME}" -n "${NS}" \
    -o jsonpath='{.status.addresses[0].value}')

  if [ -z "${GATEWAY_ADDRESS}" ]; then
    echo "❌ Gateway address is empty on real GKE."
    exit 1
  fi
else
  if [ -z "${ENVOY_SVC:-}" ]; then
    ENVOY_SVC=$(kubectl get svc -n envoy-gateway-system \
      --selector=gateway.envoyproxy.io/owning-gateway-namespace=${NS},gateway.envoyproxy.io/owning-gateway-name=${GATEWAY_NAME} \
      -o jsonpath='{.items[0].metadata.name}')
  fi

  if [ -z "${ENVOY_SVC}" ]; then
    echo "❌ Could not find Envoy Gateway service for Gateway ${NS}/${GATEWAY_NAME}."
    echo "   Hint: kubectl get svc -n envoy-gateway-system"
    exit 1
  fi
  echo "  Found Envoy service: ${ENVOY_SVC}"

  PORT_FORWARD_PORT="${PORT_FORWARD_PORT:-8060}"

  pkill -f "kubectl.*port-forward.*${PORT_FORWARD_PORT}" 2>/dev/null || true
  sleep 1

  echo "▶ Starting port-forward on localhost:${PORT_FORWARD_PORT} → svc/${ENVOY_SVC}:80..."
  kubectl -n envoy-gateway-system port-forward svc/"${ENVOY_SVC}" \
    ${PORT_FORWARD_PORT}:80 >/tmp/envoy-port-forward.log 2>&1 &
  PORT_FORWARD_PID=$!
  echo "  port-forward PID: ${PORT_FORWARD_PID}"
  echo "  log: /tmp/envoy-port-forward.log"

  sleep 2
  if ! kill -0 "${PORT_FORWARD_PID}" 2>/dev/null; then
    echo "❌ Port-forward died. See /tmp/envoy-port-forward.log"
    exit 1
  fi
  GATEWAY_ADDRESS="localhost:${PORT_FORWARD_PORT}"
fi

# ─── 13. Print URLs ───────────────────────────────────────────────────────────
# For branch deployments, all app URLs get the /<ns>/ prefix (see step 8 patches)
if [ "$TARGET_NS" = "project" ]; then
  APP_PREFIX=""
else
  APP_PREFIX="/${TARGET_NS}"
fi

PINGPONG_URL="http://${GATEWAY_ADDRESS}/pingpong"
LOG_URL="http://${GATEWAY_ADDRESS}/log"
TODO_URL="http://${GATEWAY_ADDRESS}${APP_PREFIX}/"
SUBMIT_URL="http://${GATEWAY_ADDRESS}${APP_PREFIX}/submit"
BACKEND_URL="http://${GATEWAY_ADDRESS}${APP_PREFIX}/backend"

echo ""
echo "✅ Gateway address: ${GATEWAY_ADDRESS}"
echo "   Target namespace: ${TARGET_NS}  (image tag: ${TARGET_TAG})"
echo "   Ping-pong:   ${PINGPONG_URL}"
echo "   Log-output:  ${LOG_URL}"
echo "   Todo app:    ${TODO_URL}"
echo "   Todo submit: ${SUBMIT_URL}"
echo "   Todo list:   ${BACKEND_URL}"
echo ""
echo "ℹ️  First request may return 5xx for 5–30s while backend health checks converge."
if [ -n "${PORT_FORWARD_PID}" ]; then
  echo "ℹ️  Port-forward is running as PID ${PORT_FORWARD_PID}."
  echo "   Stop it with: kill ${PORT_FORWARD_PID}"
fi
echo ""