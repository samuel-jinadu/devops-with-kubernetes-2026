#!/bin/bash

CLUSTER_NAME="k8s-lab"
KUBECONFIG_PATH="${HOME}/.kube/config"

echo "================================================"
echo "  Starting K3d cluster: ${CLUSTER_NAME}"
echo "================================================"

# Ensure .kube dir exists
mkdir -p ~/.kube

# Check if cluster already exists
if k3d cluster list 2>/dev/null | grep -q "^${CLUSTER_NAME}"; then
  SERVERS_RUNNING=$(k3d cluster list | grep "^${CLUSTER_NAME}" | awk '{print $2}')
  echo "▶ Cluster '${CLUSTER_NAME}' exists (servers: ${SERVERS_RUNNING})"

  if echo "${SERVERS_RUNNING}" | grep -q "^0/"; then
    echo "  Restarting stopped cluster..."
    k3d cluster start ${CLUSTER_NAME}
  else
    echo "  Cluster is already running ✅"
  fi
else
  echo "▶ Creating new cluster '${CLUSTER_NAME}'..."
  k3d cluster create "${CLUSTER_NAME}" \
  --api-port 127.0.0.1:6443 \
  --servers 1 \
  --agents 2 \
  --port "8080:80@loadbalancer" \
  --port "8443:443@loadbalancer" \
  --wait
  # changed from these because i no longer use node ports
  # k3d cluster create "${CLUSTER_NAME}" \
  # --api-port 127.0.0.1:6443 \
  # --servers 1 \
  # --agents 2 \
  # --port "8080:80@loadbalancer" \
  # --port "8443:443@loadbalancer" \
  # --port "8082:30080@agent:0" \
  # --port "8083:30081@agent:0" \
  # --wait
  echo "  ✅ Cluster created"
fi

# ── Merge kubeconfig ──────────────────────────────────────────────────────────
echo ""
echo "▶ Merging kubeconfig..."
k3d kubeconfig merge ${CLUSTER_NAME} \
  --kubeconfig-merge-default \
  --kubeconfig-switch-context

# Fix any host-only addresses that would be unreachable from inside the container
# (needed for clusters created before --api-port 127.0.0.1:6443 was added).
sed -i 's|https://0.0.0.0|https://127.0.0.1|g; s|https://host.docker.internal|https://127.0.0.1|g' \
  "${HOME}/.kube/config" 2>/dev/null || true

echo "  ✅ kubeconfig written to ${HOME}/.kube/config"

# Ensure KUBECONFIG is set in .bashrc for all future terminals
if ! grep -q "export KUBECONFIG" ~/.bashrc 2>/dev/null; then
  echo "export KUBECONFIG=${KUBECONFIG_PATH}" >> ~/.bashrc
fi

# Export for the current shell process too
export KUBECONFIG="${KUBECONFIG_PATH}"

echo "  ✅ kubeconfig written to ${KUBECONFIG_PATH}"

# ── Wait for nodes to be Ready ────────────────────────────────────────────────
echo ""
echo "▶ Waiting for nodes to be Ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=60s

echo ""
echo "▶ Cluster info:"
echo ""
kubectl get nodes -o wide
echo ""
echo "================================================"
echo "  ✅ Cluster ready! Try:"
echo ""
echo "     kubectl get nodes"
echo "     kubectl get pods -A"
echo "     k9s"
echo "================================================"