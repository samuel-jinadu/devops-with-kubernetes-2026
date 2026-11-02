#!/bin/bash
set -euo pipefail

NS=exercises

echo "════ 1. Namespaces + Gateway ════"
kubectl apply -f manifests/namespaces

kubectl -n "$NS" delete statefulset postgres-stset    --ignore-not-found
kubectl -n "$NS" delete deployment  pingpong-dep      --ignore-not-found
kubectl -n "$NS" delete deployment  hashgenerator-dep --ignore-not-found
sleep 5

echo "════ 2. Ping-pong + log-output (no DB) ════"
kubectl apply -f ping-pong/gke-manifests
kubectl apply -f log-output/gke-manifests

echo "════ 3. Waiting for pods to settle ════"
for i in $(seq 1 30); do
  n=$(kubectl -n "$NS" get pods --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
  if [ "$n" -ge 2 ]; then break; fi
  sleep 3
done
sleep 10  # let probes fire at least once

echo ""
echo "════ BEFORE DB ════"
kubectl -n "$NS" get pods
echo ""
echo "Expected:"
echo "  pingpong-dep-*   0/1  Running    ← /readyz returns 503 (no DB)"
echo "  hashgenerator-*  0/1  Running    ← /readyz returns 503 (pingpong not-ready)"
echo ""

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