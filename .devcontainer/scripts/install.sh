#!/bin/bash

echo "================================================"
echo "  Installing K3d Kubernetes Learning Environment"
echo "================================================"

# ── k3d ──────────────────────────────────────────────────────────────────────
if command -v k3d &>/dev/null; then
  echo "▶ k3d already installed ($(k3d version | head -1 | awk '{print $3}')) — skipping"
else
  echo ""
  echo "▶ Installing k3d..."
  curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
  echo "  ✅ k3d $(k3d version | head -1 | awk '{print $3}') installed"
fi

# ── kubectx + kubens ─────────────────────────────────────────────────────────
if command -v kubectx &>/dev/null; then
  echo "▶ kubectx/kubens already installed — skipping"
else
  echo ""
  echo "▶ Installing kubectx and kubens..."
  sudo git clone https://github.com/ahmetb/kubectx /opt/kubectx --quiet
  sudo ln -sf /opt/kubectx/kubectx /usr/local/bin/kubectx
  sudo ln -sf /opt/kubectx/kubens /usr/local/bin/kubens
  echo "  ✅ kubectx and kubens installed"
fi

# ── k9s ──────────────────────────────────────────────────────────────────────
if command -v k9s &>/dev/null; then
  echo "▶ k9s already installed — skipping"
else
  echo ""
  echo "▶ Installing k9s..."
  K9S_VERSION=$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest | grep tag_name | cut -d'"' -f4)
  if [ -z "$K9S_VERSION" ]; then
    echo "  ⚠️  Could not fetch k9s version — skipping"
  else
    curl -sL "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_amd64.tar.gz" | \
      sudo tar xz -C /usr/local/bin k9s
    echo "  ✅ k9s ${K9S_VERSION} installed"
  fi
fi

# ── Stern ────────────────────────────────────────────────────────────────────
if command -v stern &>/dev/null; then
  echo "▶ stern already installed — skipping"
else
  echo ""
  echo "▶ Installing stern..."
  STERN_VERSION=$(curl -s https://api.github.com/repos/stern/stern/releases/latest | grep tag_name | cut -d'"' -f4)
  if [ -z "$STERN_VERSION" ]; then
    echo "  ⚠️  Could not fetch stern version — skipping"
  else
    curl -sL "https://github.com/stern/stern/releases/download/${STERN_VERSION}/stern_linux_amd64.tar.gz" | \
      sudo tar xz -C /usr/local/bin stern
    echo "  ✅ stern ${STERN_VERSION} installed"
  fi
fi

# ── kubectl aliases (idempotent) ──────────────────────────────────────────────
if grep -q "# ── Kubernetes shortcuts" ~/.bashrc 2>/dev/null; then
  echo "▶ kubectl aliases already configured — skipping"
else
  echo ""
  echo "▶ Setting up kubectl aliases and shell completion..."
  cat >> ~/.bashrc << 'BASHRC'

# ── Kubernetes shortcuts ──────────────────────────────────────────────────────
alias k="kubectl"
alias kgp="kubectl get pods"
alias kgs="kubectl get svc"
alias kgd="kubectl get deployments"
alias kgn="kubectl get nodes"
alias kga="kubectl get all"
alias kdp="kubectl describe pod"
alias kds="kubectl describe svc"
alias kl="kubectl logs"
alias kaf="kubectl apply -f"
alias kdf="kubectl delete -f"
alias kns="kubens"
alias kctx="kubectx"

# kubectl autocomplete
source <(kubectl completion bash)
complete -F __start_kubectl k
BASHRC
  echo "  ✅ Aliases and completion configured"
fi

# ── Go ───────────────────────────────────────────────────────────────────────
if [ -x /usr/local/go/bin/go ] || command -v go &>/dev/null; then
  GO_INSTALLED_VERSION=$(
    /usr/local/go/bin/go version 2>/dev/null || go version
  ) 
  echo "▶ Go already installed (${GO_INSTALLED_VERSION}) — skipping"
else
  echo ""
  echo "▶ Installing Go..."

  # Prefer the version declared in go.mod; fall back to the latest stable release.
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

  GO_VERSION=""
  for mod in "${WORKSPACE_ROOT}/log-output/go.mod" "${WORKSPACE_ROOT}/todo-app/go.mod"; do
    if [ -f "$mod" ]; then
      GO_VERSION=$(awk '/^go /{print $2; exit}' "$mod")
      break
    fi
  done
  if [ -z "$GO_VERSION" ]; then
    GO_VERSION=$(curl -fsS 'https://go.dev/VERSION?m=text' | head -1 | sed 's/^go//')
  fi

  case "$(uname -m)" in
    x86_64)  GO_ARCH="amd64" ;;
    aarch64|arm64) GO_ARCH="arm64" ;;
    *) echo "  ⚠️  Unsupported architecture: $(uname -m) — skipping"; GO_ARCH="" ;;
  esac

  if [ -z "$GO_VERSION" ] || [ -z "$GO_ARCH" ]; then
    echo "  ⚠️  Could not determine Go version or architecture — skipping"
  else
    if curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" -o /tmp/go.tar.gz; then
      sudo rm -rf /usr/local/go
      sudo tar -C /usr/local -xzf /tmp/go.tar.gz
      rm -f /tmp/go.tar.gz
      echo "  ✅ Go ${GO_VERSION} installed"
    else
      echo "  ⚠️  Go ${GO_VERSION} download failed — skipping"
    fi
  fi

  # Persist PATH for future shells (idempotent)
  if ! grep -q "/usr/local/go/bin" ~/.bashrc 2>/dev/null; then
    cat >> ~/.bashrc << 'BASHRC'

# ── Go ──────────────────────────────────────────────────────────────────────
export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
BASHRC
  fi

  # And for the current script's environment
  export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
fi

# ── SOPS ─────────────────────────────────────────────────────────────────────
if command -v sops &>/dev/null; then
  echo "▶ sops already installed ($(sops --version | head -1)) — skipping"
else
  echo ""
  echo "▶ Installing sops..."
  SOPS_VERSION=$(curl -s https://api.github.com/repos/getsops/sops/releases/latest | grep tag_name | cut -d'"' -f4)
  if [ -z "$SOPS_VERSION" ]; then
    echo "  ⚠️  Could not fetch sops version — skipping"
  else
    curl -sL "https://github.com/getsops/sops/releases/download/${SOPS_VERSION}/sops_${SOPS_VERSION#v}_amd64.deb" -o /tmp/sops.deb
    sudo dpkg -i /tmp/sops.deb >/dev/null
    rm -f /tmp/sops.deb
    echo "  ✅ sops ${SOPS_VERSION} installed"
  fi
fi

# ── age ──────────────────────────────────────────────────────────────────────
if command -v age-keygen &>/dev/null; then
  echo "▶ age already installed — skipping"
else
  echo ""
  echo "▶ Installing age..."
  sudo apt-get update -qq
  sudo apt-get install -y age >/dev/null
  echo "  ✅ age installed"
fi

# ── Helm ─────────────────────────────────────────────────────────────────────
if command -v helm &>/dev/null; then
  echo "▶ Helm already installed ($(helm version --short 2>/dev/null)) — skipping"
else
  echo ""
  echo "▶ Installing Helm..."
  curl -fsSL -o /tmp/get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
  chmod 700 /tmp/get_helm.sh
  /tmp/get_helm.sh
  rm -f /tmp/get_helm.sh
  echo "  ✅ Helm $(helm version --short 2>/dev/null) installed"
fi

# ── floci-gcp (GCP emulator) ──────────────────────────────────────────────────
echo ""
echo "▶ Setting up floci-gcp (GCP emulator)..."

# Start floci-gcp if not already running
if docker ps --filter "name=floci-gcp" --format '{{.Names}}' | grep -q '^floci-gcp$'; then
  echo "  floci-gcp already running — skipping start"
else
  docker rm -f floci-gcp 2>/dev/null || true
  docker run -d --name floci-gcp \
    -p 4588:4588 \
    -v /var/run/docker.sock:/var/run/docker.sock \
    floci/floci-gcp:latest >/dev/null
  echo "  ✅ floci-gcp container started"

  # Wait for the emulator API to answer before returning
  echo "  ⏳ Waiting for floci-gcp to be ready..."
  for i in $(seq 1 30); do
    if curl -fsS http://localhost:4588/ >/dev/null 2>&1 || \
       curl -fsS http://localhost:4588/container/v1/projects >/dev/null 2>&1; then
      echo "  ✅ floci-gcp is up"
      break
    fi
    sleep 1
    if [ "$i" -eq 30 ]; then
      echo "  ⚠️  floci-gcp did not respond within 30s — continuing anyway"
    fi
  done
fi

# Persist env vars for every future shell (idempotent)
if ! grep -q "# ── floci-gcp env" ~/.bashrc 2>/dev/null; then
  cat >> ~/.bashrc << 'BASHRC'

# ── floci-gcp env ─────────────────────────────────────────────────────────────
export CLOUDSDK_API_ENDPOINT_OVERRIDES_CONTAINER="http://localhost:4588/container/"
export CLOUDSDK_API_ENDPOINT_OVERRIDES_SERVICEUSAGE="http://localhost:4588/"
export CLOUDSDK_CORE_PROJECT="floci-local"
export CLOUDSDK_AUTH_ACCESS_TOKEN="floci"
BASHRC
  echo "  ✅ floci-gcp env vars added to ~/.bashrc"
fi

# Export for the current script's environment too
export CLOUDSDK_API_ENDPOINT_OVERRIDES_CONTAINER="http://localhost:4588/container/"
export CLOUDSDK_CORE_PROJECT="floci-local"
export CLOUDSDK_AUTH_ACCESS_TOKEN="unused"

echo "  ✅ floci-gcp ready — gcloud will target the emulator in this workspace"

# ── Google Cloud SDK (gcloud) ────────────────────────────────────────────────
if command -v gcloud &>/dev/null; then
  echo "▶ gcloud CLI already installed ($(gcloud --version | head -1)) — skipping"
else
  echo ""
  echo "▶ Installing Google Cloud SDK (gcloud)..."

  # Install prerequisites
  sudo apt-get update -qq
  sudo apt-get install -y apt-transport-https ca-certificates gnupg curl >/dev/null

  # Add the Google Cloud SDK repository (cleanly, overwriting any duplicates)
  curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | \
    sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
  
  # Use 'tee' to overwrite the file, preventing duplicate entries
  echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | \
    sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list >/dev/null

  # Update and install gcloud CLI + the *correctly named* auth plugin
  sudo apt-get update -qq
  sudo apt-get install -y google-cloud-cli google-cloud-cli-gke-gcloud-auth-plugin >/dev/null

  if command -v gcloud &>/dev/null; then
    echo "  ✅ gcloud $(gcloud --version | head -1) installed"
  else
    echo "  ❌ gcloud installation failed. Check the apt output above."
    exit 1 # Fail the script so the user knows something is wrong
  fi
fi

# ── ensure .kube dir exists ───────────────────────────────────────────────────
mkdir -p ~/.kube

echo ""
echo "================================================"
echo "  ✅ Installation complete!"
echo "================================================"