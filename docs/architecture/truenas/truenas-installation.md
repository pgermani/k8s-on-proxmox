# TrueNAS SCALE Installation and Configuration

Below is the process used to install and configure **TrueNAS SCALE** within the homelab platform.

TrueNAS runs as a virtual machine on Proxmox VE with direct disk passthrough, acting as the storage backend and providing both **NFS** and **SMB** services for Kubernetes workloads and local network access.

All configuration steps were performed using the TrueNAS SCALE web interface.

Official download page:
https://www.truenas.com/download/


## 1. Downloading TrueNAS SCALE ISO

1. Navigate to the official TrueNAS download page.
2. Copy the direct ISO download URL.
3. In Proxmox:
   - Navigate to **Datacenter -> `<proxmox-node>` -> local -> ISO Images -> Download from URL**
   - Paste the copied TrueNAS ISO URL

This makes the ISO available to the hypervisor for VM creation.

## 2. Creating the Virtual Machine

**Datacenter -> `<proxmox-node>` -> Create VM**

### General

- VM ID: `101`
- Name: `TrueNAS-Scale`
- Start at boot: **Enabled**

### OS

- ISO Image: TrueNAS SCALE (downloaded above)

### System

- Default settings

### Disk

- Disk size: `50 GB`
- Storage: `local-lvm`
- Bus: VirtIO

> This disk is used only for the TrueNAS OS installation.
> Data disks are attached separately via passthrough.

### CPU & Memory

- CPU: 4 vCPUs
- RAM: 8 GB

### Network

- Default bridge: `vmbr0` (default Proxmox LAN bridge)
- Model: VirtIO

### Boot

- Start after creation: Enabled

After review, click **Finish** to create the VM.

## 3. Installing TrueNAS SCALE

1. Start the VM and open the console.
2. The installer launches automatically.
3. Select: `Install/Upgrade`
4. Choose the assigned 50 GB virtual disk as installation target.
5. Confirm installation.
6. Configure:
   - Administrative user password
   - Web UI authentication
   - EFI boot (enabled)
7. Wait for installation to complete.
8. Reboot the VM when prompted.

After rebooting, the console displays the IP address assigned to TrueNAS SCALE.

## 4. Initial Web Configuration

1. Open a browser and navigate to: `http://<TrueNAS-IP>`
2. Log in using the configured administrative credentials.

At this point TrueNAS is operational and ready for:

   - [Disk Passthrough Configuration](storage/disk-passthrough.md)
   - [Dataset-Shares service setup](storage/dataset-shares-setup.md)