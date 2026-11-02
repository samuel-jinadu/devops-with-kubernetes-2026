#!/bin/bash

# 1. Check the exact service name
kubectl -n monitoring get svc

# 2. Port-forward to the Prometheus server service 
kubectl port-forward svc/prometheus-kube-prometheus-prometheus -n monitoring 9090:9090

