# Proxmox VM Template with Ubuntu Cloud Image (Cloud-Init)

Below is the process I use to create a reusable Ubuntu VM template on Proxmox VE using official Ubuntu Cloud Images and cloud-init.

This template forms the baseline for provisioning Kubernetes control plane and worker nodes in a consistent and reproducible way.

## Prerequisites

1. Install **Proxmox VE** on your host:

   - Official guide: https://www.proxmox.com/en/products/proxmox-virtual-environment/get-started

   >  Prepare the installation media using preferred USB flashing tool (e.g. https://etcher.balena.io/).

2. (Optional but recommended for homelab setups) Run the community post-install script:

   https://community-scripts.github.io/ProxmoxVE/scripts?id=post-pve-install

   This script applies common homelab adjustments, such as enabling the no-subscription repository and disabling enterprise subscription notifications.

   > Review the script before executing it. It is community-maintained and not officially supported by Proxmox.

After Proxmox installation, ensure:

- Networking is correctly configured (`vmbr0`)
- Storage (e.g. `local-lvm`) is available

## 1. Connect to the Proxmox Host

All the following commands must be executed on the Proxmox node.

Connect via SSH from your local machine:

```bash
ssh root@<proxmox-ip>
```

## 2. Download Ubuntu Cloud Image

Use an official Ubuntu LTS cloud image:

```bash
wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
```

Cloud images are minimal images designed specifically for cloud-init initialization.

> Use the latest supported Ubuntu LTS release (e.g. Jammy or Noble).

## 3. Create an Empty VM

```bash
qm create 8000 \
  --name ubuntu-cloud-template \
  --memory 2048 \
  --cores 2 \
  --net0 virtio,bridge=vmbr0
```

Adjust CPU and memory according to your baseline requirements.

## 4. Import the Cloud Disk

Import the downloaded image into your Proxmox storage:

```bash
qm disk import 8000 noble-server-cloudimg-amd64.img local-lvm
```

Replace `local-lvm` with your storage if needed.


## 5. Attach the Disk as Primary SCSI

```bash
qm set 8000 \
  --scsihw virtio-scsi-pci \
  --scsi0 local-lvm:vm-8000-disk-0
```

## 6. Add the Cloud-Init Drive

```bash
qm set 8000 --ide2 local-lvm:cloudinit
```

Cloud-init will handle:

- SSH key injection
- User configuration
- Network settings
- Hostname initialization

## 7. Configure Boot Order

```bash
qm set 8000 --boot c --bootdisk scsi0
```

## 8. Enable Serial Console (useful for debugging)


```bash
qm set 8000 --serial0 socket --vga serial0
```

## 9. Configure Cloud-Init Parameters

You can configure via CLI or GUI.

### CLI

```bash
qm set 8000 \
  --ciuser ubuntu \
  --sshkey ~/.ssh/id_rsa.pub
```

```bash
qm set 8000 \
  --ipconfig0 ip=<node-ip>/<cidr>,gw=<default-gateway-ip>
```

Example:
```bash
qm set 8000 \
  --ipconfig0 ip=192.168.0.178/24,gw=192.168.0.1
```

Do **not** start the VM before converting it to template.

### GUI

1. Select the VM.
2. Open the **Cloud-Init** tab.
3. Configure:
   - **User** (e.g. `ubuntu`)
   - **SSH Public Key**
   - **IP Configuration**
     - `Static`
       - IP: `<node-ip>/<cidr>`
       - Gateway: `<default-gateway-ip>`

       Example:
         - IP: `192.168.0.178/24`
         - Gateway: `192.168.0.1`
4. Click **Regenerate Image** after making changes.


## 10. Convert VM to Template

### CLI

```bash
qm template 8000
```

### GUI

1. Right-click the VM.
2. Select **Convert to Template**.

> This operation is irreversible. The VM becomes a reusable template and cannot be started directly anymore.


## 11. Clone the Template

### CLI

```bash
qm clone <template-vmid> <new-vmid> --name <vm-name> --full
```

Example:

```bash
qm clone 8000 8101 --name k8s-worker-01 --full
```

### GUI

1. Select the Template.
2. Right-click -> **Clone**.
3. Set:
   - **VM ID** -> Increment from the last created VM
   - **Mode** -> Full Clone
   - **Name** -> Descriptive name (e.g. `k8s-worker-01`)
4. Click **Clone**.


## 12. Post-Clone

After cloning, review the VM configuration before starting it.

1. Open the cloned VM.
2. Verify **Cloud-Init -> IP Configuration**:
   - Ensure the assigned static IP is not already in use.
   - Confirm the gateway and network settings are correct.
3. Adjust hardware resources according to node role:
   - CPU cores
   - Memory allocation
   - Disk size

Start the VM and verify SSH access using the injected public key.
