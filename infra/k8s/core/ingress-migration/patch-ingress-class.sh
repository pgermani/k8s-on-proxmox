#!/bin/bash
# Phase 1 - Assign an explicit ingressClassName to every Ingress in the cluster.
#
# Ingress resources without an explicit class are claimed by whichever
# controller holds the default IngressClass. With two controllers running this
# causes a race on the Ingress status subresource, so every resource must be
# pinned to "nginx" before Traefik is started.
#
# The manifests under infra/k8s/apps/*/ingress.yaml already declare
# `ingressClassName: nginx`. This script catches anything created outside the
# repo - most notably the Rancher Ingress in cattle-system.
#
# See docs/k8s/core/ingress-traefik-migration.md
set -eo pipefail

kubectl get ingress --all-namespaces \
  -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name' --no-headers |
  while read -r NS NAME; do
    echo "Patching Ingress: ${NS}/${NAME}"
    kubectl patch ingress "$NAME" -n "$NS" \
      --type=merge -p '{"spec": {"ingressClassName": "nginx"}}'
  done

echo
echo "==> Current state:"
kubectl get ingress --all-namespaces \
  -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,ICLASS:.spec.ingressClassName'
