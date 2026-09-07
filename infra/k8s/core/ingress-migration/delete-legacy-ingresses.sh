#!/bin/bash
# Phase 4 - Delete the legacy nginx-class Ingress resources.
#
# Run this only after phase 3 is verified and all applications are reachable
# through Traefik on ports 80/443. The "-traefik" duplicates created in phase 2
# are left untouched.
#
# > Note: the equivalent snippet in the RKE2 documentation ends its awk filter
# > with `exit`, which stops after the first match and deletes a single Ingress.
# > This version iterates over all of them.
#
# See docs/k8s/core/ingress-traefik-migration.md
set -eo pipefail

kubectl get ingress --all-namespaces \
  -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,ICLASS:.spec.ingressClassName' --no-headers |
  awk '$3 == "nginx" { print $1, $2 }' |
  while read -r NS NAME; do
    echo "Deleting legacy Ingress: ${NS}/${NAME}"
    kubectl delete ingress "$NAME" -n "$NS"
  done

echo
echo "==> Current state:"
kubectl get ingress --all-namespaces \
  -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,ICLASS:.spec.ingressClassName'
