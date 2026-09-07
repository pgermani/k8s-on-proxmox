#!/bin/bash
# Phase 2 - Duplicate every nginx-class Ingress for parallel validation.
#
# Each copy is suffixed with "-traefik" and reclassified to
# "rke2-ingress-nginx-migration", so Traefik serves it on ports 8000/8443 while
# the original keeps serving production traffic on 80/443 through Ingress NGINX.
#
# Cluster-assigned metadata is stripped before reapplying, otherwise the API
# server rejects the copy.
#
# Requires: jq
#
# See docs/k8s/core/ingress-traefik-migration.md
set -eo pipefail

command -v jq >/dev/null || { echo "jq is required"; exit 1; }

kubectl get ingress --all-namespaces \
  -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,ICLASS:.spec.ingressClassName' --no-headers |
  awk '$3 == "nginx" { print $1, $2 }' |
  while read -r NS NAME; do
    echo "Duplicating Ingress: ${NS}/${NAME} -> ${NAME}-traefik"
    kubectl get ingress "$NAME" -n "$NS" -o json |
      jq --arg name "${NAME}-traefik" '
        .metadata.name = $name
        | .spec.ingressClassName = "rke2-ingress-nginx-migration"
        | del(
            .metadata.resourceVersion,
            .metadata.uid,
            .metadata.creationTimestamp,
            .metadata.generation,
            .metadata.managedFields,
            .metadata.ownerReferences,
            .metadata.annotations["kubectl.kubernetes.io/last-applied-configuration"],
            .status
          )
      ' | kubectl apply -f -
  done

echo
echo "==> Current state:"
kubectl get ingress --all-namespaces \
  -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,ICLASS:.spec.ingressClassName'
