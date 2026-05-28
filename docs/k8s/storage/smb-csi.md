# SMB CSI Driver (csi-driver-smb)

Below is how the SMB CSI driver is installed and used in this homelab to mount TrueNAS SMB shares as static PersistentVolumes inside the RKE2 cluster.

Unlike the NFS provisioner, SMB volumes are **static**: each PV is defined manually and bound to a specific share path on TrueNAS. This is the right model for shared media libraries, application config directories, or any storage that is accessed both from the cluster and from desktop clients simultaneously.

The setup involves four independent pieces that build on each other:

1. The CSI driver (Helm) - runs on every node and handles mount/unmount
2. A headless Service + Endpoints - exposes the TrueNAS SMB server inside the cluster by DNS name
3. A Secret with SMB credentials - replicated across namespaces via [Reflector](../core/reflector.md)
4. PersistentVolume + PersistentVolumeClaim - one PV/PVC pair per application, each pointing to the application's dedicated path on TrueNAS

---

## 1. Prerequisites

| Requirement | Details |
|---|---|
| Running RKE2 cluster | See [rke2-bootstrap.md](../../rke2-bootstrap.md) |
| SMB share on TrueNAS | See [dataset-shares-setup.md](../../truenas/storage/dataset-shares-setup.md) |
| Reflector installed | See [reflector.md](../core/reflector.md) |
| `helm` on local machine | [Official install guide](https://helm.sh/docs/intro/install/) |

---

## 2. Install the CSI Driver

```bash
helm repo add csi-driver-smb https://raw.githubusercontent.com/kubernetes-csi/csi-driver-smb/master/charts
helm repo update
helm install csi-driver-smb csi-driver-smb/csi-driver-smb \
  --namespace kube-system \
  --version v1.18.0
```

Verify the driver pods are running on every node:

```bash
kubectl get pods -n kube-system -l app=csi-smb-node
```

Expected output: one pod per node, all `Running`.

---

## 3. Expose TrueNAS SMB Inside the Cluster

Rather than hardcoding the TrueNAS IP in every PV, a headless Service with manually-defined Endpoints is created in the `external-services` namespace. This makes the SMB server reachable inside the cluster via the stable DNS name `smb-server.external-services.svc.cluster.local`.

The manifest is at `infra/k8s/core/storage/smb-csi/smb-server-service.yaml`. Replace `<TRUENAS-IP>` with the actual TrueNAS LAN IP before applying.

```bash
kubectl create namespace external-services
kubectl apply -f infra/k8s/core/storage/smb-csi/smb-server-service.yaml
```

---

## 4. SMB Credentials Secret

Create the `smb-creds` Secret in the `external-services` namespace using the SMB user configured in TrueNAS (see [dataset-shares-setup.md - section 4.1](../../truenas/storage/dataset-shares-setup.md)).

Fill in the credentials in `infra/k8s/core/storage/smb-csi/smb-creds-secret.yaml`, then apply:

```bash
kubectl apply -f infra/k8s/core/storage/smb-csi/smb-creds-secret.yaml
```

Then annotate it for Reflector so it is automatically replicated to every namespace that mounts SMB volumes:

```bash
kubectl annotate secret smb-creds -n external-services \
  reflector.v1.k8s.emberstack.com/reflection-allowed="true" \
  reflector.v1.k8s.emberstack.com/reflection-auto-enabled="true"
```

> See [reflector.md](../core/reflector.md) for details on how to restrict replication to specific namespaces only.

---

## 5. PersistentVolume

SMB volumes are static: each PV is defined manually and points to a specific path on the TrueNAS share. The `volumeHandle` must be **unique** across all PVs in the cluster.

The `storageClassName` is a free-form label used only to bind the PV to the matching PVC - no StorageClass object is required.

Naming convention used in this setup:

| Field | Pattern | Example |
|---|---|---|
| PV name | `pv-<app>-smb-<pool>` | `pv-jellyfin-smb` |
| `volumeHandle` | `<app>-smb-<pool>` | `jellyfin-smb` |
| `storageClassName` | `smb-<pool>-<dataset>` | `smb-media` |

An example manifest is at `infra/k8s/core/storage/smb-csi/pv-example.yaml`.

> `nodeStageSecretRef.namespace` must match the namespace where the PVC will be created - that is where Reflector has placed a copy of `smb-creds`.

---

## 6. PersistentVolumeClaim

Each application gets its own PVC referencing the PV by name. The `storageClassName` must match the one on the PV.

An example manifest is at `infra/k8s/core/storage/smb-csi/pvc-example.yaml`.

Apply the PV first, then the PVC:

```bash
kubectl apply -f pv-<app>.yaml
kubectl apply -f pvc-<app>.yaml
```

Verify the PVC is bound:

```bash
kubectl get pvc -n <namespace>
```

Expected status: `Bound`.

