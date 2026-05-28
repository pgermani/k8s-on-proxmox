# cert-manager

Below is how cert-manager is installed in this homelab to manage TLS certificates inside the RKE2 cluster.

## 1. Prerequisites

| Requirement | Details |
|---|---|
| Running RKE2 cluster | See [rke2-bootstrap.md](../../rke2-bootstrap.md) |
| `helm` on local machine | [Official install guide](https://helm.sh/docs/intro/install/) |


## 2. Install cert-manager

Add the Jetstack repository and install cert-manager with CRDs:

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true
```

Verify the pods are running:

```bash
kubectl get pods --namespace cert-manager
```

Expected output: three pods, all `Running`:

```
NAME                                       READY   STATUS    RESTARTS   AGE
cert-manager-<hash>                        1/1     Running   0          1m
cert-manager-cainjector-<hash>             1/1     Running   0          1m
cert-manager-webhook-<hash>                1/1     Running   0          1m
```
