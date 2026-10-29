#!/bin/bash

echo "▶ waiting for Grafana…"
kubectl -n monitoring rollout status deployment/my-kube-prometheus-stack-grafana --timeout=180s

echo "port-forwarding for monitoring stack (Ctrl-C to exit)"
kubectl port-forward -n monitoring svc/my-kube-prometheus-stack-grafana 3000:80