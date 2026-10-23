#!/bin/bash

kubectl apply -f todo-app/manifests/deployment.yaml
kubectl apply -f log-output/manifests/deployment.yaml