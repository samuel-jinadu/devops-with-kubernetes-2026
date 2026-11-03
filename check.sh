#!/bin/bash
kubectl get pods -n exercises
kubectl get pods -n staging
kubectl get pods -n production 2>/dev/null || echo "(production not yet deployed — waiting for first tag)"