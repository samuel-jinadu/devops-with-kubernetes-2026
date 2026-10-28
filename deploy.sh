#!/bin/bash



docker exec k3d-k8s-lab-agent-0 mkdir -p /tmp/kube # Ensuring dir exists for persistent-volume.spec.local.path
kubectl apply -f manifests -R

sops --decrypt postgres/postgres-credentials.enc.yaml | kubectl apply -f -
kubectl apply -f postgres/postgres.yaml 

kubectl apply -f todo-backend/manifests
kubectl apply -f todo-app/manifests
kubectl apply -f log-output/manifests
kubectl apply -f ping-pong/manifests