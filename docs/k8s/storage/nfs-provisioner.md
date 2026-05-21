# NFS Dynamic Provisioner (nfs-subdir-external-provisioner)

The `nfs-subdir-external-provisioner` runs inside the RKE2 cluster and watches for PVCs referencing the `nfs-truenas` StorageClass. For each one, it automatically creates a dedicated subdirectory on the TrueNAS NFS export and binds it to a PersistentVolume — no manual PV creation needed.

This provisioner consumes the NFS share configured in TrueNAS as described in [dataset-shares-setup.md](../../truenas/storage/dataset-shares-setup.md).

---

## 1. Prerequisites

| Requirement | Details |
|---|---|
| Running RKE2 cluster | See [rke2-bootstrap.md](../../rke2-bootstrap.md) |
| NFS share on TrueNAS | See [dataset-shares-setup.md](../../truenas/storage/dataset-shares-setup.md) |
| `nfs-common` on all nodes | Installed automatically by the bootstrap script |
| `helm` on local machine | [Official install guide](https://helm.sh/docs/intro/install/) |

> The bootstrap script installs `nfs-common` on all nodes. If you provisioned nodes manually, run `sudo apt-get install -y nfs-common` on each before proceeding.

---

## 2. Installation

Add the Helm repository and install the provisioner:

```bash
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/

helm repo update

helm install nfs-subdir-external-provisioner \
  nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --namespace nfs \
  --create-namespace \
  --set nfs.server=<TRUENAS-IP> \
  --set nfs.path=<NFS-DATASET-PATH> \
  --set storageClass.name=nfs-truenas \
  --set storageClass.defaultClass=false \
  --set storageClass.onDelete=true \
  --set nfs.mountOptions='{nfsvers=4}'
```

| Parameter | Value | Notes |
|---|---|---|
| `nfs.server` | `<TRUENAS-IP>` | TrueNAS LAN IP |
| `nfs.path` | `<NFS-DATASET-PATH>` | Full path to the NFS dataset, e.g. `/mnt/<pool-name>/volumes` |
| `storageClass.name` | `nfs-truenas` | Name used in PVC `storageClassName` fields |
| `storageClass.defaultClass` | `false` | Does not make this the cluster-default StorageClass |
| `storageClass.onDelete` | `true` | Deletes the NFS subdirectory when the PVC is deleted |
| `nfs.mountOptions` | `nfsvers=4` | Forces NFSv4 - required for TrueNAS NFSv4 exports |

> **`storageClass.onDelete=true`**: when a PVC is deleted, the corresponding subdirectory on TrueNAS is also removed. Set to `false` to retain data after PVC deletion - useful for stateful workloads where data must survive a redeploy.

---

## 3. Verify the Installation

Check that the provisioner pod is running and the StorageClass has been created:

```bash
kubectl get pods -n nfs
kubectl get storageclass
```

Expected output:

```
NAME                                              READY   STATUS    RESTARTS   AGE
nfs-subdir-external-provisioner-<hash>            1/1     Running   0          1m
```

```
NAME          PROVISIONER                                          RECLAIMPOLICY   VOLUMEBINDINGMODE   AGE
nfs-truenas   cluster.local/nfs-subdir-external-provisioner       Delete          Immediate           1m
```

---

## 4. Testing

The test manifests are available at `infra/k8s/core/storage/nfs-provisioner/`.

### 4.1 Create a PVC

```bash
kubectl apply -f infra/k8s/core/storage/nfs-provisioner/test-pvc.yaml
```

Wait for it to bind:

```bash
kubectl get pvc test-pvc
```

Expected status: `Bound`. If it stays `Pending`, check the provisioner logs:

```bash
kubectl logs -n nfs -l app=nfs-subdir-external-provisioner
```

### 4.2 Create a Test Pod

```bash
kubectl apply -f infra/k8s/core/storage/nfs-provisioner/test-pod.yaml
```

The pod writes a timestamped entry to the mounted volume every 10 seconds. Verify it is running:

```bash
kubectl logs nfs-test-pod -f
```

You can also confirm the file was created on TrueNAS by browsing the NFS dataset path from any machine with NFS access.

### 4.3 Cleanup

Delete the test resources once done:

```bash
kubectl delete pod nfs-test-pod
kubectl delete pvc test-pvc
```

> Deleting the PVC also removes the subdirectory on TrueNAS (because `storageClass.onDelete=true`). Verify on TrueNAS that the directory is gone after deletion.

---

## 5. Uninstall

To remove the provisioner:

```bash
helm uninstall nfs-subdir-external-provisioner -n nfs
```

> This removes the provisioner and its StorageClass. Existing PVs, PVCs, and data on TrueNAS are not affected.
