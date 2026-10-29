#!/bin/bash
set -euo pipefail

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

# ─── 2. Namespaces (must exist before the Gateway) ────────────────────────────
kubectl apply -f manifests/namespaces

# ─── 3. Decide which GatewayClass to use (real GKE vs emulator) ───────────────
GATEWAY_CLASS=""
if kubectl get gatewayclass gke-l7-global-external-managed &>/dev/null; then
  echo "▶ Real GKE detected; using GKE-managed GatewayClass."
  GATEWAY_CLASS="gke-l7-global-external-managed"
else
  echo "▶ GKE GatewayClass not found; assuming emulator; installing Envoy Gateway..."

  # Standard Gateway API CRDs (idempotent)
  kubectl apply --server-side -f \
    https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.0/standard-install.yaml

  # Envoy Gateway controller (idempotent — upgrade --install is safe on re-run)
  helm upgrade --install eg oci://docker.io/envoyproxy/gateway-helm \
    --version v1.5.4 \
    -n envoy-gateway-system --create-namespace

  kubectl wait --for=condition=Available deployment/envoy-gateway \
    -n envoy-gateway-system --timeout=300s

  GATEWAY_CLASS="eg"
fi

# ─── 4. Apply Gateway (patched on the fly; source file untouched) ─────────────
#
# NOTE: we do NOT use `kubectl apply -f gke-manifests` here. That directory
# currently only contains gateway.yaml, and applying it directly would revert
# the class patch on the emulator. If you add more files to gke-manifests/ in
# the future, apply them individually *after* this block.
sed "s|gatewayClassName: .*|gatewayClassName: ${GATEWAY_CLASS}|" \
  gke-manifests/gateway.yaml | kubectl apply -f -

# ─── 5. Secrets (decrypted from sops) ─────────────────────────────────────────
sops --decrypt postgres/postgres-credentials.enc.yaml         | kubectl apply -f -
sops --decrypt postgres/postgres-credentials-project.enc.yaml | kubectl apply -f -

# ─── 6. Postgres ──────────────────────────────────────────────────────────────
kubectl apply -f postgres/postgres.yaml
echo "▶ waiting for Postgres…"
kubectl -n exercises rollout status statefulset/postgres-stset --timeout=180s

# ─── 7. Applications (GKE manifests: workloads + HTTPRoutes) ──────────────────
kubectl apply -f ping-pong/gke-manifests
echo "▶ waiting for ping-pong…"
kubectl -n exercises rollout status deployment/pingpong-dep --timeout=120s

kubectl apply -f log-output/gke-manifests
echo "▶ waiting for log-output…"
kubectl -n exercises rollout status deployment/hashgenerator-dep --timeout=120s

# ─── 8. Wait for the Gateway to be Programmed ─────────────────────────────────
GATEWAY_NAME="exercises-gateway"
NAMESPACE="exercises"
echo "▶ Waiting for Gateway to be Programmed..."
kubectl wait --for=condition=Programmed gateway/"${GATEWAY_NAME}" \
  -n "${NAMESPACE}" --timeout=600s

# ─── 9. Resolve the Gateway address ───────────────────────────────────────────
GATEWAY_ADDRESS=""
PORT_FORWARD_PID=""

if [ "${GATEWAY_CLASS}" = "gke-l7-global-external-managed" ]; then
  # Real GKE: the address is populated on the Gateway status
  GATEWAY_ADDRESS=$(kubectl get gateway/"${GATEWAY_NAME}" -n "${NAMESPACE}" \
    -o jsonpath='{.status.addresses[0].value}')

  if [ -z "${GATEWAY_ADDRESS}" ]; then
    echo "❌ Gateway address is empty on real GKE."
    exit 1
  fi
else
  # Emulator: Envoy Gateway is behind a Service; port-forward for reliability
  echo "▶ Emulator detected; locating Envoy Gateway service..."
  ENVOY_SVC=$(kubectl get svc -n envoy-gateway-system \
    --selector=gateway.envoyproxy.io/owning-gateway-namespace=${NAMESPACE},gateway.envoyproxy.io/owning-gateway-name=${GATEWAY_NAME} \
    -o jsonpath='{.items[0].metadata.name}')

  if [ -z "${ENVOY_SVC}" ]; then
    echo "❌ Could not find Envoy Gateway service for Gateway ${NAMESPACE}/${GATEWAY_NAME}."
    echo "   Hint: kubectl get svc -n envoy-gateway-system"
    exit 1
  fi
  echo "  Found Envoy service: ${ENVOY_SVC}"

  PORT_FORWARD_PORT=8080
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

# ─── 10. Print URLs ───────────────────────────────────────────────────────────
PINGPONG_URL="http://${GATEWAY_ADDRESS}/pingpong"
LOG_URL="http://${GATEWAY_ADDRESS}/log"

echo ""
echo "✅ Gateway address: ${GATEWAY_ADDRESS}"
echo "   Ping-pong:  ${PINGPONG_URL}"
echo "   Log-output: ${LOG_URL}"
echo ""
echo "ℹ️  First request may return 5xx for 5–30s while backend health checks converge."
if [ -n "${PORT_FORWARD_PID}" ]; then
  echo "ℹ️  Port-forward is running as PID ${PORT_FORWARD_PID}."
  echo "   Stop it with: kill ${PORT_FORWARD_PID}"
fi
echo ""