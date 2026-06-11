# Jellyfin

Below is how Jellyfin is deployed in this homelab as the self-hosted media server.

Jellyfin uses a two-volume storage model: NFS for configuration and cache (dynamic provisioning via `nfs-truenas`), and SMB for the media library (static PV pointing to TrueNAS). Media is organized into category subdirectories on the TrueNAS share and mounted as separate paths inside the container.


## 1. Prerequisites

| Requirement | Details |
|---|---|
| Running RKE2 cluster | See [rke2-bootstrap.md](../../rke2-bootstrap.md) |
| NFS provisioner | See [nfs-provisioner.md](../storage/nfs-provisioner.md) - config PVC uses `nfs-truenas` |
| SMB CSI driver | See [smb-csi.md](../storage/smb-csi.md) - media PV uses `smb.csi.k8s.io` |
| `smb-creds` Secret | Must exist in the `external-services` namespace with Reflector replication enabled - see [smb-csi.md section 4](../storage/smb-csi.md) |
| Wildcard TLS certificate | See [cert-manager-cloudflare.md](../core/cert-manager-cloudflare.md) - `wildcard-prod-tls` must be available in the `jellyfin` namespace via Reflector |
| SMB media share on TrueNAS | Share path: `data/media` on the pool - see [dataset-shares-setup.md](../../truenas/storage/dataset-shares-setup.md) |


## 2. Storage Layout

| Volume | Type | Mount path | Purpose |
|---|---|---|---|
| `pvc-jellyfin` | NFS dynamic | `/config`, `/cache` | Jellyfin config and transcoding cache |
| `pvc-jellyfin-smb` | SMB static | `/films`, `/tv-series`, `/anime`, `/christmas`, `/shows` | Media library |

The SMB PV maps `//smb-server.external-services.svc.cluster.local/data/media` to the cluster. Each media category is a subdirectory under `data/media/tv/` on TrueNAS and is mounted at its own path inside the container so Jellyfin sees them as separate libraries. SMB is used instead of NFS for the media library because the same share can be mounted simultaneously from desktop clients, making it easy to add or manage files.

The `smb-creds` Secret is referenced in the `jellyfin` namespace. Reflector replicates it there automatically once the annotation is set on the source Secret in `external-services`.


## 3. Deploy

Apply all manifests in order:

```bash
kubectl apply -f infra/k8s/apps/jellyfin/namespace.yaml
kubectl apply -f infra/k8s/apps/jellyfin/pv.yaml
kubectl apply -f infra/k8s/apps/jellyfin/pvc.yaml
kubectl apply -f infra/k8s/apps/jellyfin/service.yaml
kubectl apply -f infra/k8s/apps/jellyfin/deployment.yaml
kubectl apply -f infra/k8s/apps/jellyfin/ingress.yaml
```

> Replace `<JELLYFIN-HOSTNAME>.<YOUR-DOMAIN>` in `ingress.yaml` with the actual hostname before applying.

Verify the PVCs are bound and the pod is running:

```bash
kubectl get pvc -n jellyfin
kubectl get pods -n jellyfin
```

Expected PVC status: `Bound`. Expected pod status: `Running`.


## 4. Post-Deploy: Initial Setup

Open `https://<JELLYFIN-HOSTNAME>.<YOUR-DOMAIN>` in a browser. The first-run wizard will prompt for:

1. **Display language** — select preferred language
2. **Admin account** — create the admin user and password
3. **Media libraries** — add each category as a library:

| Library name | Type | Path |
|---|---|---|
| Films | Movies | `/films` |
| TV Series | Shows | `/tv-series` |
| Anime | Shows | `/anime` |
| Christmas | Movies or Shows | `/christmas` |
| Shows | Shows | `/shows` |

4. **Metadata language** — select preferred language and country
5. Finish the wizard — Jellyfin will begin scanning the media directories

> The initial scan can take several minutes depending on library size.
