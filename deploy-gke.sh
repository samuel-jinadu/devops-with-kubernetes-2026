#!/bin/bash
set -euo pipefail


gcloud container clusters create dwk-cluster \
    --zone=europe-north1-b \
    --num-nodes=2 \
    --machine-type=e2-small

# Wait for the cluster itself to be RUNNING
echo "▶ waiting for cluster to be RUNNING…"
until [ "$(gcloud container clusters list --zone=europe-north1-b \
  --filter="name=dwk-cluster" --format="value(status)")" = "RUNNING" ]; do
  sleep 5
done

gcloud container clusters get-credentials dwk-cluster --zone=europe-north1-b
kubectl wait --for=condition=Ready nodes --all --timeout=180s


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