#!/bin/bash
set -euo pipefail

NS=exercises

echo "════ 1. Namespaces + Gateway ════"
kubectl apply -f manifests/namespaces
kubectl apply -f gke-manifests/gateway.yaml

echo "════ 2. Ping-pong + log-output (no DB) ════"
kubectl apply -f ping-pong/gke-manifests
kubectl apply -f log-output/gke-manifests

echo "════ 3. Waiting 25s for pods to settle ════"
sleep 25

echo ""
echo "════ BEFORE DB ════"
kubectl -n "$NS" get pods
echo ""
echo "Expected:"
echo "  pingpong-dep-*   0/1  Running    ← /readyz returns 503 (no DB)"
echo "  hashgenerator-*  0/1  Running    ← /readyz returns 503 (pingpong not-ready)"
echo ""
echo "Hit Enter to apply postgres..."
read -r

echo "════ 4. Applying postgres ════"
kubectl apply -f postgres/postgres.yaml
kubectl -n "$NS" rollout status statefulset/postgres-stset --timeout=180s

echo "════ 5. Waiting 30s for readiness to flip ════"
sleep 30

echo ""
echo "════ AFTER DB ════"
kubectl -n "$NS" get pods
echo ""
echo "Expected:"
echo "  pingpong-dep-*   1/1  Running"
echo "  hashgenerator-*  1/1  Running"