#!/bin/bash
set -eo pipefail

# -- Configuration ----------------------------------------------------------
SSH_USER="<ssh-user>"
CERT_PATH="<path-to-ssh-key>"
MASTER="<master-ip>"
CONTEXT_NAME="homelab"           # Name assigned to cluster, user, and context

KUBECONFIG_TMP="./kubeconfig-rke2.yaml"

# -- Helper ----------------------------------------------------
sed_inplace() {
  if [[ "$(uname)" == "Darwin" ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

# -- Download ---------------------------------------------------------------
echo "==> Downloading kubeconfig from control plane..."
ssh -i "$CERT_PATH" "${SSH_USER}@${MASTER}" "sudo cat /etc/rancher/rke2/rke2.yaml" > "$KUBECONFIG_TMP"

# -- Patch server address ---------------------------------------------------
echo "==> Patching server address to ${MASTER}..."
sed_inplace "s/127.0.0.1/${MASTER}/g" "$KUBECONFIG_TMP"

# -- Rename default context -------------------------------------------------
echo "==> Renaming context to '${CONTEXT_NAME}'..."
sed_inplace "s/: default/: ${CONTEXT_NAME}/g" "$KUBECONFIG_TMP"

# -- Merge or copy ----------------------------------------------------------
mkdir -p ~/.kube

if [ ! -f ~/.kube/config ]; then
  echo "==> No existing kubeconfig found. Copying to ~/.kube/config..."
  cp "$KUBECONFIG_TMP" ~/.kube/config
else
  echo "==> Existing kubeconfig found. Merging contexts..."
  KUBECONFIG=~/.kube/config:"$KUBECONFIG_TMP" \
    kubectl config view --flatten > ./kubeconfig-merged.yaml
  mv ./kubeconfig-merged.yaml ~/.kube/config
fi

chmod 600 ~/.kube/config
rm -f "$KUBECONFIG_TMP"

echo "==> Done. Active contexts:"
kubectl config get-contexts
