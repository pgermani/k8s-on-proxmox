# Rancher

Below is how Rancher is installed in this homelab as the web UI for managing the RKE2 cluster.


## 1. Prerequisites

| Requirement | Details |
|---|---|
| Running RKE2 cluster | See [rke2-bootstrap.md](../../rke2-bootstrap.md) |
| cert-manager installed | See [cert-manager.md](cert-manager.md) |
| NGINX Ingress Controller | Bundled with RKE2 - available by default |
| `helm` on local machine | [Official install guide](https://helm.sh/docs/intro/install/) |
| Pi-hole running | See [load-balancer.md](../../load-balancer.md) |


## 2. Install Rancher

Add the Rancher stable repository and install Rancher in the `cattle-system` namespace:

```bash
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
helm repo update

kubectl create namespace cattle-system

helm install rancher rancher-stable/rancher \
  --namespace cattle-system \
  --set hostname=<RANCHER-HOSTNAME> \
  --set bootstrapPassword=<BOOTSTRAP-PASSWORD>
```

| Parameter | Notes |
|---|---|
| `hostname` | The DNS name used to reach Rancher - must match the Pi-hole record added in step 4, e.g. `rancher.homelab` |
| `bootstrapPassword` | Temporary password for the first login - change it immediately after accessing the UI |


## 3. Verify the Deployment

Wait for the rollout to complete:

```bash
kubectl -n cattle-system rollout status deploy/rancher
```

Then confirm the deployment is healthy:

```bash
kubectl -n cattle-system get deploy rancher
```

Expected output: `READY 3/3` (Rancher runs 3 replicas by default).


## 4. Configure Internal DNS

Rather than editing `/etc/hosts` on individual machines, add a DNS record in Pi-hole so the hostname resolves for every device on the network.

1. Open the Pi-hole web UI
2. Navigate to **Local DNS -> DNS Records**
3. Add a new record:
   - **Domain**: `<RANCHER-HOSTNAME>` (e.g. `rancher.homelab`)
   - **IP Address**: `<LB-IP>` (the load balancer VM's LAN IP)
4. Click **Add**

Since Pi-hole is configured as the primary resolver on the home router (FRITZ!Box or equivalent), the record is immediately available to all devices on the home network.


## 5. Access Rancher

Open a browser and navigate to:

```
https://<RANCHER-HOSTNAME>
```

On the first login, use the bootstrap password set during installation. Rancher will prompt you to set a permanent password immediately after.

> The browser will show a certificate warning on the first visit - Rancher uses a self-signed certificate by default.


## 6. Upgrade

To upgrade Rancher to a newer version:

```bash
helm repo update

helm upgrade rancher rancher-stable/rancher \
  --namespace cattle-system \
  --reuse-values
```

> `--reuse-values` preserves the `hostname` and other settings from the original install. To change the hostname at upgrade time, pass `--set hostname=<NEW-HOSTNAME>` alongside `--reuse-values` - the explicit `--set` takes precedence.
