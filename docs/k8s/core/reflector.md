# Reflector

Below is how Reflector is deployed and used in this homelab to automatically replicate Secrets across namespaces.

Instead of duplicating a Secret in every namespace that needs it, Reflector watches a source Secret and keeps copies in sync everywhere. In this setup it is used, for example, to replicate the `smb-creds` Secret, defined once in `default`, to every namespace that mounts SMB volumes.

---

## 1. Prerequisites

| Requirement | Details |
|---|---|
| Running RKE2 cluster | See [rke2-bootstrap.md](../../rke2-bootstrap.md) |
| `helm` on local machine | [Official install guide](https://helm.sh/docs/intro/install/) |

---

## 2. Installation

```bash
kubectl create namespace reflector

helm repo add emberstack https://emberstack.github.io/helm-charts
helm repo update

helm upgrade --install reflector emberstack/reflector -n reflector
```

Verify the pod is running:

```bash
kubectl get pods -n reflector
```

Expected output:

```
NAME                         READY   STATUS    RESTARTS   AGE
reflector-<hash>             1/1     Running   0          1m
```

---

## 3. Annotating a Secret for Auto-Replication

Once Reflector is running, annotate the source Secret in its origin namespace to enable automatic replication.

The example below uses the `smb-creds` Secret in `default`:

```bash
kubectl annotate secret smb-creds -n default \
  reflector.v1.k8s.emberstack.com/reflection-allowed="true" \
  reflector.v1.k8s.emberstack.com/reflection-auto-enabled="true"
```

| Annotation | Effect |
|---|---|
| `reflection-allowed` | Permits other namespaces to request a copy of this secret |
| `reflection-auto-enabled` | Reflector automatically creates a copy in every namespace |

> By default, `reflection-auto-enabled` replicates to **all** namespaces. To restrict replication to specific namespaces, add the annotation below:
>
> ```bash
> reflector.v1.k8s.emberstack.com/reflection-auto-namespaces="headscale,jellyfin,gokapi"
> ```

---

## 4. Verify Replication

Create a test namespace and confirm the secret appears automatically:

```bash
kubectl create namespace test-reflection
kubectl get secret smb-creds -n test-reflection
```

Expected output:

```
NAME        TYPE     DATA   AGE
smb-creds   Opaque   2      <1m
```

Clean up:

```bash
kubectl delete namespace test-reflection
```

