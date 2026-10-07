#!/bin/bash
# Phase 4 - Promote every "-traefik" Ingress to its final name.
#
# By this point every application has been converted to the native "traefik"
# class (see docs/k8s/core/ingress-traefik-migration.md, section 10) and the
# legacy nginx-class originals have been deleted (delete-legacy-ingresses.sh).
# What is left is a naming leftover from phase 2: the live, working Ingress
# for each app is still called "<name>-traefik", a duplicate suffix that no
# longer means anything now that there is only one controller.
#
# Kubernetes has no rename operation. This creates a copy under the final
# name (same spec, cluster-assigned metadata stripped - same pattern as
# duplicate-ingresses.sh) and deletes the "-traefik" original.
#
# Run delete-legacy-ingresses.sh FIRST: the plain name is still held by the
# dead nginx-class original until that script removes it.
#
# Requires: jq
#
# See docs/k8s/core/ingress-traefik-migration.md
set -eo pipefail

command -v jq >/dev/null || { echo "jq is required"; exit 1; }

kubectl get ingress --all-namespaces \
  -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name' --no-headers |
  awk '$2 ~ /-traefik$/ { print $1, $2 }' |
  while read -r NS NAME; do
    FINAL_NAME="${NAME%-traefik}"
    echo "Promoting Ingress: ${NS}/${NAME} -> ${FINAL_NAME}"
    kubectl get ingress "$NAME" -n "$NS" -o json |
      jq --arg name "$FINAL_NAME" '
        .metadata.name = $name
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
    kubectl delete ingress "$NAME" -n "$NS"
  done

echo
echo "==> Current state:"
kubectl get ingress --all-namespaces \
  -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,ICLASS:.spec.ingressClassName'
