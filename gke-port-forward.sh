#!/bin/bash

kubectl port-forward -n exercises svc/pingpong-service-lb 8090:80