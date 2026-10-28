#!/bin/bash

sops --encrypt postgres/postgres-credentials.yaml \
  > postgres/postgres-credentials.enc.yaml