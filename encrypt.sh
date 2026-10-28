#!/bin/bash

sops --encrypt postgres/postgres-credentials.yaml > postgres/postgres-credentials.enc.yaml
sops --encrypt postgres/postgres-credentials-project.yaml > postgres/postgres-credentials-project.enc.yaml