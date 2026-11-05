#!/bin/bash
set -euo pipefail

CLUSTER_NAME="knative-lab"
KNATIVE_VERSION="v1.21.3"
KOURIER_VERSION="v1.21.1"

echo "================================================"
echo "  Knative Serving on k3d (exercise 5.6)"
echo "================================================"

# ── Helper: apply a remote YAML with retries ───────────────────────────
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

# ── 1. Create or start the cluster ─────────────────────────────────────
if k3d cluster list 2>/dev/null | grep -q "^${CLUSTER_NAME}"; then
  SERVERS=$(k3d cluster list | grep "^${CLUSTER_NAME}" | awk '{print $2}')
  echo "▶ Cluster '${CLUSTER_NAME}' exists (servers: ${SERVERS})"
  if echo "$SERVERS" | grep -q "^0/"; then
    echo "  Starting stopped cluster..."
    k3d cluster start "${CLUSTER_NAME}"
  fi
else
  echo "▶ Creating cluster '${CLUSTER_NAME}' (Traefik disabled)..."
  k3d cluster create "${CLUSTER_NAME}" \
    --port 8082:30080@agent:0 \
    -p 8081:80@loadbalancer \
    --agents 2 \
    --k3s-arg "--disable=traefik@server:0" \
    --image rancher/k3s:v1.34.1-k3s1 \
    --wait
  echo "  ✅ Cluster created"
fi

k3d kubeconfig merge "${CLUSTER_NAME}" \
  --kubeconfig-merge-default --kubeconfig-switch-context >/dev/null

echo "▶ Waiting for nodes..."
kubectl wait --for=condition=Ready nodes --all --timeout=120s

# ── 2. Knative Serving CRDs + core ─────────────────────────────────────
echo "▶ Installing Knative Serving CRDs..."
apply_remote \
  "https://github.com/knative/serving/releases/download/knative-${KNATIVE_VERSION}/serving-crds.yaml" \
  "Knative Serving CRDs"

echo "▶ Installing Knative Serving core..."
apply_remote \
  "https://github.com/knative/serving/releases/download/knative-${KNATIVE_VERSION}/serving-core.yaml" \
  "Knative Serving core"

# ── 3. Kourier networking layer ────────────────────────────────────────
echo "▶ Installing Kourier..."
apply_remote \
  "https://github.com/knative-extensions/net-kourier/releases/download/knative-${KOURIER_VERSION}/kourier.yaml" \
  "Kourier"

echo "▶ Telling Knative to use Kourier..."
kubectl patch configmap/config-network \
  --namespace knative-serving \
  --type merge \
  --patch '{"data":{"ingress-class":"kourier.ingress.networking.knative.dev"}}'

# ── 4. Wait for components to come up ─────────────────────────────────
echo "▶ Waiting for Knative Serving deployments..."
for d in controller webhook activator autoscaler; do
  kubectl -n knative-serving rollout status deployment/"$d" --timeout=300s 2>/dev/null || \
    echo "  ⚠ $d not ready yet — check: kubectl get pods -n knative-serving"
done

echo "▶ Waiting for Kourier deployments..."
for d in $(kubectl -n kourier-system get deploy -o name); do
  kubectl -n kourier-system rollout status "$d" --timeout=300s 2>/dev/null || \
    echo "  ⚠ $d not ready yet — check: kubectl get pods -n kourier-system"
done

# ── 5. Magic DNS (sslip.io) ────────────────────────────────────────────
echo "▶ Configuring Magic DNS (sslip.io)..."
apply_remote \
  "https://github.com/knative/serving/releases/download/knative-${KNATIVE_VERSION}/serving-default-domain.yaml" \
  "Knative magic DNS (serving-default-domain)"

kubectl -n knative-serving wait --for=condition=Complete job/default-domain --timeout=120s 2>/dev/null || \
  echo "  ⚠ default-domain job still running — check: kubectl -n knative-serving get jobs"

# ── 6. Status ──────────────────────────────────────────────────────────
echo ""
echo "================================================"
echo "  ✅ Setup complete"
echo "================================================"
echo ""
echo "Knative Serving:"
kubectl get pods -n knative-serving
echo ""
echo "Kourier:"
kubectl get pods -n kourier-system
echo ""
echo "Next steps:"
echo "  kubectl apply -f knative/hello-world.yaml"
echo "  kubectl get ksvc"