#!/bin/bash
set -eo pipefail

# -- Configuration ----------------------------------------------------------
INSTALL_RKE2_VERSION="v1.32.7+rke2r1"

SSH_USER="<ssh-user>"
CERT_PATH="<path-to-ssh-key>"

MASTER="<master-ip>"
WORKER1="<worker1-ip>"
WORKER2="<worker2-ip>"

WORKERS=("$WORKER1" "$WORKER2")

# -- Control plane ----------------------------------------------------------

echo "==> Installing RKE2 server on ${MASTER}... (version: ${INSTALL_RKE2_VERSION})"
ssh -i "$CERT_PATH" "${SSH_USER}@${MASTER}" <<EOF
  set -e

  # Disable services that interfere with Kubernetes networking
  sudo systemctl disable --now apparmor.service  || true
  sudo systemctl disable --now firewalld.service || true
  sudo systemctl disable --now ufw               || true

  # Disable swap (required by kubelet)
  sudo swapoff -a
  sudo sed -i '/ swap / s/^/#/' /etc/fstab

  sudo apt-get update -q
  sudo apt-get upgrade -y -q
  sudo apt-get autoremove -y -q
  sudo apt-get install -y -q curl nfs-common

  curl -sfL https://get.rke2.io | sudo INSTALL_RKE2_VERSION="$INSTALL_RKE2_VERSION" sh -
  sudo systemctl enable --now rke2-server.service

  # Set up kubeconfig for the $SSH_USER user
  while [ ! -f /etc/rancher/rke2/rke2.yaml ]; do
    sleep 2
  done
  sudo mkdir -p /home/${SSH_USER}/.kube
  sudo cp /etc/rancher/rke2/rke2.yaml /home/${SSH_USER}/.kube/config
  sudo chown -R ${SSH_USER}:${SSH_USER} /home/${SSH_USER}/.kube
  echo "export KUBECONFIG=/home/${SSH_USER}/.kube/config" | sudo tee -a /home/${SSH_USER}/.bashrc

  # Symlink the bundled kubectl into PATH
  sudo ln -sf \$(find /var/lib/rancher/rke2/data/ -name kubectl) /usr/local/bin/kubectl
EOF

# -- Wait for the node-token to be generated --------------------------------

echo "==> Waiting for control-plane node-token..."
while ! ssh -i "$CERT_PATH" "${SSH_USER}@${MASTER}" sudo test -f /var/lib/rancher/rke2/server/node-token; do
  echo "    token not ready yet, retrying in 5s..."
  sleep 5
done

NODE_TOKEN=$(ssh -i "$CERT_PATH" "${SSH_USER}@${MASTER}" "sudo cat /var/lib/rancher/rke2/server/node-token")

# -- Worker nodes -----------------------------------------------------------

for worker in "${WORKERS[@]}"; do
  echo "==> Installing RKE2 agent on ${worker}... (version: ${INSTALL_RKE2_VERSION})"
  ssh -i "$CERT_PATH" "${SSH_USER}@${worker}" <<EOF
  set -e

  sudo systemctl disable --now apparmor.service  || true
  sudo systemctl disable --now firewalld.service || true
  sudo systemctl disable --now ufw               || true

  sudo swapoff -a
  sudo sed -i '/ swap / s/^/#/' /etc/fstab

  sudo apt-get update -q
  sudo apt-get upgrade -y -q
  sudo apt-get autoremove -y -q
  sudo apt-get install -y -q curl nfs-common

  curl -sfL https://get.rke2.io | sudo INSTALL_RKE2_VERSION="$INSTALL_RKE2_VERSION" INSTALL_RKE2_TYPE="agent" sh -

  sudo mkdir -p /etc/rancher/rke2
  printf 'server: https://${MASTER}:9345\ntoken: ${NODE_TOKEN}\n' | sudo tee /etc/rancher/rke2/config.yaml

  sudo systemctl enable --now rke2-agent.service
EOF
done

# -- Local kubeconfig -------------------------------------------------------

echo "==> Downloading kubeconfig from control plane..."
ssh -i "$CERT_PATH" "${SSH_USER}@${MASTER}" "sudo cat /etc/rancher/rke2/rke2.yaml" > ./kubeconfig-rke2.yaml

echo "==> Patching kubeconfig server address to ${MASTER}..."
if sed --version >/dev/null 2>&1; then
  sed -i "s/127.0.0.1/${MASTER}/g" ./kubeconfig-rke2.yaml
else
  # macOS requires an explicit backup suffix
  sed -i '' "s/127.0.0.1/${MASTER}/g" ./kubeconfig-rke2.yaml
fi

echo "==> Done. Kubeconfig written to ./kubeconfig-rke2.yaml"
