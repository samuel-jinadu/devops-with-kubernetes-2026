#!/bin/bash

docker exec k3d-k8s-lab-agent-0 mkdir -p /tmp/kube # Ensuring dir exists for persistent-volume.spec.local.path
kubectl apply -f manifests -R

kubectl apply -f todo-backend/manifests
kubectl apply -f todo-app/manifests
kubectl apply -f log-output/manifests
kubectl apply -f ping-pong/manifests