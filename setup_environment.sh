#!/usr/bin/env bash
set -euo pipefail

# setup_environment.sh
# Installs Python, creates a virtualenv and installs required Python packages and Ansible collections
# Works on Debian/Ubuntu and RHEL/Fedora (dnf) based systems. Run from project root.

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
REQ_FILE="$ROOT_DIR/python-requirements.txt"
GALAXY_REQ_FILE="$ROOT_DIR/ansible-requirements.yml"
VENV_DIR="$ROOT_DIR/.venv"

echo "Running setup_environment.sh from $ROOT_DIR"

if [ ! -f "$REQ_FILE" ]; then
  echo "requirements.txt not found at $REQ_FILE"
  exit 1
fi

# detect package manager
if command -v apt-get >/dev/null 2>&1; then
  PKG_MANAGER=apt
elif command -v dnf >/dev/null 2>&1; then
  PKG_MANAGER=dnf
elif command -v yum >/dev/null 2>&1; then
  PKG_MANAGER=yum
else
  echo "Unsupported package manager. Please install Python 3.9+, pip and required build tools manually."
  exit 1
fi

echo "Using package manager: $PKG_MANAGER"

if [ "$PKG_MANAGER" = "apt" ]; then
  echo "Updating apt and installing system packages (requires sudo)"
  # Ensure script subprocesses use a UTF-8 locale early
  export LANG=${LANG:-en_US.UTF-8}
  export LC_ALL=${LC_ALL:-en_US.UTF-8}

  sudo apt-get update -y
  sudo apt-get install -y python3 python3-venv python3-pip build-essential libssl-dev libffi-dev locales jq genisoimage xorriso

  # Enable en_US.UTF-8 on Debian/Ubuntu systems. Write /etc/locale.gen if needed,
  # generate locales and set a system default so Ansible subprocesses won't fail with
  # "unsupported locale setting" when run as root.
  if ! grep -q -E "^en_US.UTF-8\s+UTF-8" /etc/locale.gen >/dev/null 2>&1; then
    echo "en_US.UTF-8 UTF-8" | sudo tee -a /etc/locale.gen >/dev/null || true
  fi
  sudo locale-gen en_US.UTF-8 || true
  # localedef may be needed on some minimal images
  sudo localedef -i en_US -f UTF-8 en_US.UTF-8 >/dev/null 2>&1 || true
  # Persist the system locale
  echo "LANG=en_US.UTF-8" | sudo tee /etc/default/locale >/dev/null || true
  sudo update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 >/dev/null 2>&1 || true
elif [ "$PKG_MANAGER" = "dnf" ]; then
  echo "Installing system packages with dnf (requires sudo)"
  sudo dnf install -y python3 python3-venv python3-pip gcc python3-devel redhat-rpm-config glibc-langpack-en || true
  # set system locale (non-fatal if fails)
  sudo localectl set-locale LANG=en_US.UTF-8 || true
elif [ "$PKG_MANAGER" = "yum" ]; then
  echo "Installing system packages with yum (requires sudo)"
  sudo yum install -y python3 python3-venv python3-pip gcc python3-devel redhat-rpm-config glibc-langpack-en || true
  sudo localectl set-locale LANG=en_US.UTF-8 || true
fi

# Create virtualenv
if [ ! -d "$VENV_DIR" ]; then
  echo "Creating Python virtualenv in $VENV_DIR"
  python3 -m venv "$VENV_DIR"
else
  echo "Virtualenv already exists at $VENV_DIR"
fi

# Verify presence of a tool to create ISO images (genisoimage/mkisofs/xorriso)
if ! command -v genisoimage >/dev/null 2>&1 && ! command -v mkisofs >/dev/null 2>&1 && ! command -v xorriso >/dev/null 2>&1; then
  echo "Warning: no ISO creation tool found (genisoimage/mkisofs/xorriso). Some role tasks create Talos config ISOs."
  echo "On Debian/Ubuntu: sudo apt-get install -y genisoimage xorriso"
  echo "On RHEL/Fedora: sudo dnf install -y xorriso" 
  echo "You can set KUBECTL_DOWNLOAD_URL and TALOSCTL_DOWNLOAD_URL if downloads are blocked by a proxy."
fi

# Activate and install python packages
echo "Installing Python packages into virtualenv"
# shellcheck disable=SC1090
source "$VENV_DIR/bin/activate"
python -m pip install --upgrade pip setuptools wheel
python -m pip install -r "$REQ_FILE"

# Ensure ansible-galaxy is available (provided by ansible-core)
if ! command -v "$VENV_DIR/bin/ansible-galaxy" >/dev/null 2>&1; then
  echo "ansible-galaxy not found in venv; ensure ansible-core is installed in the venv"
  echo "You can activate the venv and install ansible-core manually:"
  echo "  source $VENV_DIR/bin/activate && pip install 'ansible-core>=2.12'"
  deactivate || true
  exit 1
fi

# Install required Ansible collections
echo "Installing required Ansible collections into virtualenv"
# Ensure a UTF-8 locale is exported for subprocesses (fixes Ansible locale initialization errors)
export LANG=${LANG:-en_US.UTF-8}
export LC_ALL=${LC_ALL:-en_US.UTF-8}

# Run ansible-galaxy under an explicit UTF-8 environment. Use bash -lc wrapper so the
# virtualenv's ansible-galaxy is used and environment variables are applied reliably
# even when running as root or under restricted shells. Retry once with PATH set.
ANSIBLE_GALAXY_CMD="$VENV_DIR/bin/ansible-galaxy install -r $GALAXY_REQ_FILE"
env LANG="$LANG" LC_ALL="$LC_ALL" bash -lc "$ANSIBLE_GALAXY_CMD" || {
  echo "Primary ansible-galaxy attempt failed; retrying with explicit PATH set"
  env LANG="$LANG" LC_ALL="$LC_ALL" PATH="$VENV_DIR/bin:$PATH" bash -lc "$ANSIBLE_GALAXY_CMD"
}

echo "Ensure helm is installed"
if ! command -v helm >/dev/null 2>&1; then
  echo "helm not found, attempting to download latest release"
  HELM_LATEST_TAG="$(curl -fsSL https://api.github.com/repos/helm/helm/releases/latest | jq -r '.tag_name')"
  HELM_DOWNLOAD_URL="https://get.helm.sh/helm-${HELM_LATEST_TAG}-linux-amd64.tar.gz"
  if [ -n "$HELM_LATEST" ]; then
    echo "Downloading helm from $HELM_DOWNLOAD_URL"
    curl -fsSL "$HELM_DOWNLOAD_URL" -o /tmp/helm.tar.gz
    tar -xzf /tmp/helm.tar.gz -C /tmp
    sudo mv /tmp/linux-amd64/helm /usr/local/bin/helm
    sudo chmod +x /usr/local/bin/helm
    rm -f /tmp/helm.tar.gz
    rm -rf /tmp/linux-amd64
  else
    echo "Could not determine helm latest release; please install helm manually"
  fi
else
  echo "helm already installed"
fi

echo "Ensure talosctl is installed"
if ! command -v talosctl >/dev/null 2>&1; then
  echo "talosctl not found, attempting to download latest release"
  TALOS_LATEST="$(curl -fsSL https://api.github.com/repos/siderolabs/talos/releases/latest | grep -E "browser_download_url.*talosctl-linux-amd64" | head -n1 | cut -d '"' -f4)"
  if [ -n "$TALOS_LATEST" ]; then
    echo "Downloading talosctl from $TALOS_LATEST"
    sudo curl -fsSL "$TALOS_LATEST" -o /usr/local/bin/talosctl
    sudo chmod +x /usr/local/bin/talosctl
  else
    echo "Could not determine talosctl latest release; please install talosctl manually"
  fi
else
  echo "talosctl already installed"
fi

echo "Ensure kubectl is installed"
if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl not found, attempting to download latest stable release"
  # Allow override via environment variable for air-gapped or proxied environments
  if [ -n "${KUBECTL_DOWNLOAD_URL:-}" ]; then
    KUBECTL_URL="$KUBECTL_DOWNLOAD_URL"
  else
    # Use -fsSL to follow redirects; dl.k8s.io often replies with a 302 that must be followed
    KUBE_VER="$(curl -fsSL https://dl.k8s.io/release/stable.txt 2>/dev/null || true)"
    # Validate we got a plausible release (starts with 'v<number>') to avoid HTML content being captured
    if echo "$KUBE_VER" | grep -qE '^v[0-9]+'; then
      KUBECTL_URL="https://dl.k8s.io/release/${KUBE_VER}/bin/linux/amd64/kubectl"
    else
      echo "Could not determine kubectl stable release from https://dl.k8s.io/release/stable.txt"
      echo "Received: '$KUBE_VER'"
      echo "You can set KUBECTL_DOWNLOAD_URL to a direct download URL to install kubectl automatically."
      KUBECTL_URL=""
    fi
  fi

  if [ -n "${KUBECTL_URL:-}" ]; then
    echo "Downloading kubectl from $KUBECTL_URL"
    sudo curl -fsSL "$KUBECTL_URL" -o /usr/local/bin/kubectl
    sudo chmod +x /usr/local/bin/kubectl
  else
    echo "Could not determine kubectl URL; please install kubectl manually"
  fi
else
  echo "kubectl already installed"
fi

# Done
deactivate || true

cat <<EOF

Setup completed.

Next steps:
  1) Activate the virtualenv:
     source $VENV_DIR/bin/activate

  2) Run the playbook (example):
     cd ansible
     ansible-playbook site.yml -i inventory/host_vars/homelab.yml
EOF

exit 0
