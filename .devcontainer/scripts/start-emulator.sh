#!/bin/bash
set -euo pipefail

echo "================================================"
echo "  Ensuring floci-gcp emulator is running"
echo "================================================"

if docker ps --filter "name=floci-gcp" --format '{{.Names}}' | grep -q '^floci-gcp$'; then
  echo "▶ floci-gcp already running"
elif docker ps -a --filter "name=floci-gcp" --format '{{.Names}}' | grep -q '^floci-gcp$'; then
  echo "▶ floci-gcp container exists but is stopped — starting it"
  docker start floci-gcp >/dev/null
else
  echo "❌ floci-gcp container does not exist."
  echo "   Re-run postCreateCommand (Dev Containers: Rebuild Container) to reinstall."
  exit 1
fi

echo "▶ Waiting for floci-gcp API to respond on :4588…"
for i in $(seq 1 30); do
  if curl -fsS http://localhost:4588/ >/dev/null 2>&1 || \
     curl -fsS http://localhost:4588/container/v1/projects >/dev/null 2>&1; then
    echo "  ✅ floci-gcp is up"
    break
  fi
  sleep 1
  if [ "$i" -eq 30 ]; then
    echo "❌ floci-gcp did not respond within 30s"
    exit 1
  fi
done

# The CLOUDSDK_* env vars are written into ~/.bashrc by install.sh,
# but a non-login shell in postStartCommand won't have them. Export here
# so any gcloud/kubectl invocation in this shell hits the emulator.
export CLOUDSDK_API_ENDPOINT_OVERRIDES_CONTAINER="http://localhost:4588/container/"
export CLOUDSDK_API_ENDPOINT_OVERRIDES_SERVICEUSAGE="http://localhost:4588/"
export CLOUDSDK_CORE_PROJECT="floci-local"
export CLOUDSDK_AUTH_ACCESS_TOKEN="floci"

echo ""
echo "✅ Emulator ready. Next: ./deploy-gke.sh"