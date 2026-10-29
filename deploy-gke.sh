#!/bin/bash
set -euo pipefail

if ! gcloud container clusters describe dwk-cluster --zone=europe-north1-b >/dev/null 2>&1; then
  gcloud container clusters create dwk-cluster \
    --zone=europe-north1-b \
    --num-nodes=2 \
    --machine-type=e2-small
else
  echo "▶ dwk-cluster already exists; skipping creation."
fi


# Wait for the cluster itself to be RUNNING
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


# ── Ensure an Ingress controller exists (portable across GKE & emulators) ──
if ! kubectl get ingressclass -o name 2>/dev/null | grep -q .; then
  echo "▶ No IngressClass found; installing ingress-nginx..."
  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
  helm repo update
  helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
    -n ingress-nginx --create-namespace \
    --set controller.service.type=LoadBalancer \
    --set controller.watchIngressWithoutClass=true
  kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=180s
else
  echo "▶ IngressClass already present; skipping controller installation."
fi

# Namespaces
kubectl apply -f manifests/namespaces

# Secrets (decrypted with sops)
sops --decrypt postgres/postgres-credentials.enc.yaml         | kubectl apply -f -
sops --decrypt postgres/postgres-credentials-project.enc.yaml | kubectl apply -f -

# Postgres
kubectl apply -f postgres/postgres.yaml
echo "▶ waiting for Postgres…"
kubectl -n exercises rollout status statefulset/postgres-stset --timeout=180s

# Ping-pong
kubectl apply -f ping-pong/manifests
echo "▶ waiting for ping-pong…"
kubectl -n exercises rollout status deployment/pingpong-dep --timeout=120s

# Log‑output
kubectl apply -f log-output/manifests
echo "▶ waiting for log-output…"
kubectl -n exercises rollout status deployment/hashgenerator-dep --timeout=120s