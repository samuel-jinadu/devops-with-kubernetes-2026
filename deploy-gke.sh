#!/bin/bash
set -euo pipefail


gcloud container clusters create dwk-cluster \
    --zone=europe-north1-b \
    --num-nodes=2 \
    --machine-type=e2-small
gcloud container clusters get-credentials dwk-cluster --zone=europe-north1-b
kubectl get nodes   # confirm the cluster is reachable
kubectl wait --for=condition=Ready nodes --all --timeout=180s


# Namespaces
kubectl apply -f manifests/namespaces

# Secrets (decrypted from sops)
sops --decrypt postgres/postgres-credentials.enc.yaml         | kubectl apply -f -

# Postgres StatefulSet + headless Service
kubectl apply -f postgres/postgres.yaml
echo "▶ waiting for Postgres…"
kubectl -n exercises rollout status statefulset/postgres-stset --timeout=180s

# Ping-pong (init container waits for Postgres, but block here too)
kubectl apply -f ping-pong/gke-manifests
echo "▶ waiting for ping-pong…"
kubectl -n exercises rollout status deployment/pingpong-dep --timeout=120s