#!/bin/bash
set -euo pipefail

# Ensure the host dir for the local PersistentVolume exists inside the k3d agent
docker exec k3d-k8s-lab-agent-0 mkdir -p /tmp/kube

# 1. Namespaces and shared storage first (everything else references these)
kubectl apply -f manifests/namespaces
kubectl apply -f manifests/storage

# 2. Secrets (decrypted from sops)
sops --decrypt postgres/postgres-credentials.enc.yaml         | kubectl apply -f -
sops --decrypt postgres/postgres-credentials-project.enc.yaml | kubectl apply -f -

# 3. Postgres StatefulSet + headless Service
kubectl apply -f postgres/postgres.yaml
echo "▶ waiting for Postgres…"
kubectl -n exercises rollout status statefulset/postgres-stset --timeout=180s

# 4. Ping-pong (init container waits for Postgres, but block here too)
kubectl apply -f ping-pong/manifests
echo "▶ waiting for ping-pong…"
kubectl -n exercises rollout status deployment/pingpong-dep --timeout=120s

# 5. Log-output (polls ping-pong's /count — needs ping-pong up)
kubectl apply -f log-output/manifests
echo "▶ waiting for log-output…"
kubectl -n exercises rollout status deployment/hashgenerator-dep --timeout=120s

# 6. Todo-backend (depends on Postgres)
kubectl apply -f todo-backend/manifests
echo "▶ waiting for todo-backend…"
kubectl -n project rollout status deployment/todo-backend-deployment --timeout=120s

# 7. Todo-app (frontend fetches from todo-backend on every request)
kubectl apply -f todo-app/manifests
echo "▶ waiting for todo-app…"
kubectl -n project rollout status deployment/todo-app-deployment --timeout=120s

# 8. CronJob LAST — backend is guaranteed ready by now, so the first
#    scheduled run will succeed without relying on retries.
kubectl apply -f manifests/cronjobs

echo ""
echo "✅ All resources deployed and ready"