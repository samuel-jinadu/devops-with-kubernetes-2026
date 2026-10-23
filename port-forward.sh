#!/bin/bash

POD=$(kubectl get pods | grep todo | awk '{print $1}')
kubectl port-forward pod/$POD 8090:8090