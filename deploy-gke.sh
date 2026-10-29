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
    --skip-crds \
    -n envoy-gateway-system --create-namespace

  kubectl wait --for=condition=Available deployment/envoy-gateway \
    -n envoy-gateway-system --timeout=300s

  # Envoy Gateway's Helm chart does NOT create the GatewayClass.
  # Create it explicitly so exercises-gateway has something to bind to.
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

# ─── 7b. GKE-only: point the LB health check at /healthz ──────────────────────
if [ "${GATEWAY_CLASS}" = "gke-l7-global-external-managed" ]; then
  echo "▶ Applying GKE HealthCheckPolicy…"
  kubectl apply -f gke-manifests/pingpong-healthcheckpolicy.yaml
fi

# ─── 8. Wait for the Gateway data plane ───────────────────────────────────────
GATEWAY_NAME="exercises-gateway"
NAMESPACE="exercises"

if [ "${GATEWAY_CLASS}" = "gke-l7-global-external-managed" ]; then
  echo "▶ Waiting for Gateway to be Programmed (real GKE)..."
  kubectl wait --for=condition=Programmed gateway/"${GATEWAY_NAME}" \
    -n "${NAMESPACE}" --timeout=600s
else
  # Emulator: Envoy Gateway creates a Service/Deployment in envoy-gateway-system.
  # We can't rely on `Programmed=True` because floci-gcp has no LoadBalancer
  # implementation, so the Service's EXTERNAL-IP stays <pending> and the
  # Gateway condition may never flip. Waiting on the data-plane objects is
  # sufficient — we port-forward to the Service directly in step 9.
  echo "▶ Waiting for Envoy data plane to appear (emulator)..."
  ENVOY_SVC=""
  ENVOY_DEPLOY=""
  for i in $(seq 1 90); do
    ENVOY_SVC=$(kubectl get svc -n envoy-gateway-system \
      --selector=gateway.envoyproxy.io/owning-gateway-namespace=${NAMESPACE},gateway.envoyproxy.io/owning-gateway-name=${GATEWAY_NAME} \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

    ENVOY_DEPLOY=$(kubectl get deploy -n envoy-gateway-system \
      --selector=gateway.envoyproxy.io/owning-gateway-namespace=${NAMESPACE},gateway.envoyproxy.io/owning-gateway-name=${GATEWAY_NAME} \
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
      echo "         kubectl describe gateway ${GATEWAY_NAME} -n ${NAMESPACE}"
      exit 1
    fi
  done
fi

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
  # Emulator: reuse the Envoy Service discovered in step 8.
  if [ -z "${ENVOY_SVC:-}" ]; then
    ENVOY_SVC=$(kubectl get svc -n envoy-gateway-system \
      --selector=gateway.envoyproxy.io/owning-gateway-namespace=${NAMESPACE},gateway.envoyproxy.io/owning-gateway-name=${GATEWAY_NAME} \
      -o jsonpath='{.items[0].metadata.name}')
  fi

  if [ -z "${ENVOY_SVC}" ]; then
    echo "❌ Could not find Envoy Gateway service for Gateway ${NAMESPACE}/${GATEWAY_NAME}."
    echo "   Hint: kubectl get svc -n envoy-gateway-system"
    exit 1
  fi
  echo "  Found Envoy service: ${ENVOY_SVC}"

  PORT_FORWARD_PORT=8060
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