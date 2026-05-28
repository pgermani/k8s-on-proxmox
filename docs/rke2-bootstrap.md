# RKE2 Cluster Bootstrap

This guide covers bootstrapping a single-control-plane RKE2 cluster (1 CP + N workers) from scratch using the script at `infra/k8s/bootstrap/init-rke2-cluster.sh`.


## 1. Prerequisites

| Requirement | Details |
|---|---|
| VM template | Ubuntu Noble cloud-init clones - see [proxmox-cloudinit-template.md](proxmox-cloudinit-template.md) |
| SSH key | A single key pair that grants passwordless access to all nodes |
| SSH access | All nodes reachable by IP from the machine running the script |
| Outbound internet | Nodes need to reach `get.rke2.io` and the Ubuntu `apt` mirrors |
| NFS client | Installed automatically by the script (`nfs-common`) |
| `kubectl` | Installed on the local machine - [official install guide](https://kubernetes.io/docs/tasks/tools/) |
| `helm` | Installed on the local machine - [official install guide](https://helm.sh/docs/intro/install/) |

The script is designed to run from your local machine (macOS or Linux). It SSH-es into each node in sequence.


## 2. Network Layout

| Role | Hostname | IP |
|---|---|---|
| Control plane | `cp1` | `<master-ip>` |
| Worker 1 | `wrk1` | `<worker1-ip>` |
| Worker 2 | `wrk2` | `<worker2-ip>` |

> Note: These are environment-specific values. Update the variables at the top of the script before running.


## 3. Configuration

Open `infra/k8s/bootstrap/init-rke2-cluster.sh` and update the variables block:

```bash
SSH_USER="<ssh-user>"          # The user created by cloud-init on each VM
CERT_PATH="<path-to-ssh-key>"  # Path to the SSH private key (relative to where you run the script)

MASTER="<master-ip>"           # Control-plane IP
WORKER1="<worker1-ip>"         # Worker 1 IP
WORKER2="<worker2-ip>"         # Worker 2 IP
```

No other changes are needed for a standard two-worker setup. To add more workers, append to the `WORKERS` array.


## 4. What the Script Does

### Control plane bootstrap

On the control-plane node the script:

1. Disables services that conflict with Kubernetes networking: `apparmor`, `firewalld`, `ufw`.
2. Disables swap permanently (`swapoff -a` + comment out the swap entry in `/etc/fstab`).
3. Installs `nfs-common` so NFS PVCs work out of the box.
4. Downloads and installs RKE2 via the official installer (`get.rke2.io`), then enables and starts `rke2-server.service`.
5. Copies the generated `rke2.yaml` kubeconfig into `~/.kube/config` for the SSH user.
6. Symlinks the bundled `kubectl` binary into `/usr/local/bin`.

### Wait for the node token

The script polls until `/var/lib/rancher/rke2/server/node-token` exists on the control plane (created once the server is ready to accept agents), then reads it.

### Worker bootstrap

On each worker node the script:

1. Applies the same pre-flight steps (swap, services, `nfs-common`).
2. Installs RKE2 in **agent** mode (`INSTALL_RKE2_TYPE=agent`).
3. Writes `/etc/rancher/rke2/config.yaml` with the control-plane registration endpoint and the node token.
4. Enables and starts `rke2-agent.service`.

### Local kubeconfig

The `rke2.yaml` produced by RKE2 uses `127.0.0.1` as the server address. The script fetches it via SSH and rewrites the address to the control-plane LAN IP, saving the result as `./kubeconfig-rke2.yaml` in the current directory.


## 5. Running the [Script](../infra/k8s/bootstrap/init-rke2-cluster.sh)

```bash
cd infra/k8s/bootstrap
chmod +x init-rke2-cluster.sh
./init-rke2-cluster.sh
```

The script exits on any error (`set -eo pipefail`). Expected runtime: 5–10 minutes depending on apt mirrors.

Verify the cluster once it completes:

```bash
export KUBECONFIG=./kubeconfig-rke2.yaml
kubectl get nodes
```

Expected output (workers may take a minute to appear as `Ready`):

```
NAME                  STATUS   ROLES                       AGE   VERSION
<cp-vm-name>          Ready    control-plane,etcd,master   5m    v1.3x.x+rke2rX
<worker-vm-name-1>    Ready    <none>                      3m    v1.3x.x+rke2rX
<worker-vm-name-2>    Ready    <none>                      3m    v1.3x.x+rke2rX
```


## 6. Post-Install Steps

### Configure Local kubectl Client

The script saves the kubeconfig as `./kubeconfig-rke2.yaml` in the current directory. To use `kubectl` without specifying `KUBECONFIG` on every command, merge or copy it into `~/.kube/config`.

**Before copying or merging, rename the cluster, user, and context** to avoid collisions with the generic name `default` that RKE2 assigns to all three fields.

Open `kubeconfig-rke2.yaml` and replace every occurrence of `default` with a meaningful name (e.g. `homelab`):

```bash
sed -i 's/: default/: homelab/g' ./kubeconfig-rke2.yaml
```

> Note: on macOS use `sed -i '' 's/: default/: homelab/g' ./kubeconfig-rke2.yaml`.

**If `~/.kube/config` does not exist yet:**

```bash
mkdir -p ~/.kube
cp ./kubeconfig-rke2.yaml ~/.kube/config
```

**If `~/.kube/config` already contains other contexts (merge):**

```bash
KUBECONFIG=~/.kube/config:./kubeconfig-rke2.yaml \
  kubectl config view --flatten > ./kubeconfig-merged.yaml
mv ./kubeconfig-merged.yaml ~/.kube/config
chmod 600 ~/.kube/config
```

After either step, verify the active context:

```bash
kubectl config get-contexts
kubectl get nodes
```

### Label worker nodes

RKE2 agents join without a `worker` role label by default. Add it manually:

```bash
kubectl label node <worker-vm-name> node-role.kubernetes.io/worker=worker
```

> **Note:** The node name matches the VM name set in Proxmox at clone time - see [proxmox-cloudinit-template.md](proxmox-cloudinit-template.md). Use `kubectl get nodes` to confirm the exact names registered in the cluster.

### Install the SMB CSI driver

Required for static volumes backed by TrueNAS SMB shares. See [smb-csi.md](k8s/storage/smb-csi.md) for the full setup.

### Add TLS SANs to the control plane (optional)

If you expose the API server via a load balancer or a DNS name, add `tls-san` entries to `/etc/rancher/rke2/config.yaml` on the control plane then restart `rke2-server`:

```yaml
# /etc/rancher/rke2/config.yaml on the control plane
tls-san:
  - "<master-ip>"
  - "<api-dns-name>"
```

See the [RKE2 server config reference](https://docs.rke2.io/reference/server_config) for the full list of options.

