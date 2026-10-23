#!/bin/bash

kubectl apply -f todo-app/manifests/deployment.yaml
kubectl apply -f todo-app/manifests/service.yaml

kubectl apply -f log-output/manifests/deployment.yaml
kubectl apply -f log-output/manifests/service.yaml