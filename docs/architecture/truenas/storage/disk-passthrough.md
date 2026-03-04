# Disk Passthrough Configuration (Proxmox -> TrueNAS SCALE)

The following section explains how physical disks are attached directly to the **TrueNAS SCALE** virtual machine using Proxmox VE passthrough.

TrueNAS acts as the storage backend of the platform. To preserve proper disk management, SMART monitoring, and full filesystem control (ZFS), the physical disks are passed directly to the VM instead of being managed by the Proxmox host.

> Important: Disks assigned to TrueNAS must **not** be mounted or used by the Proxmox host.

## 1. Identify Physical Disks on the Proxmox Host

Identify the correct physical device before attaching it to the VM.

List block devices:

```
lsblk
```

For stable and predictable device mapping, use the disk-by-id path:

```
ls -l /dev/disk/by-id/
```

Using `/dev/disk/by-id/` is strongly recommended because:
- Device names like `/dev/sda` may change after reboot.
- Disk-by-id paths are persistent and hardware-based.


## 2. Assign the Entire Physical Disk to the VM

Attach the whole physical disk to the VM using Proxmox raw disk passthrough:

```
qm set <VMID> -scsiX /dev/disk/by-id/<DISK-ID>
```

Where:

- `<VMID>` is the ID of the virtual machine.
- `scsiX` is the SCSI bus index (e.g. `scsi1`, `scsi2`, etc.).
- `<DISK-ID>` is the persistent disk identifier located under `/dev/disk/by-id/`.

> Always use `/dev/disk/by-id/` instead of `/dev/sdX` to avoid issues caused by device renaming after reboots.

Before attaching the disk, verify which disk slots are already in use:

```bash
qm config <VMID>
```

Choose an unused `scsiX` index.

Example:

```
qm set 101 -scsi1 /dev/disk/by-id/wwn-0x5000000000004814
```

> `scsi1` is used in this example. A VirtIO block device (`virtioX`, e.g. `virtio1`) can also be used, although VirtIO SCSI is generally recommended.

After execution, the disk becomes visible inside the TrueNAS VM as a raw block device.

## 3. Verify Disk Attachment

After attaching the disk:

1. Start (or restart) the TrueNAS VM.
2. Log into the TrueNAS Web UI.
3. Navigate to:
   - **Storage -> Disks**

The passthrough disk should now appear and be available for pool creation.


## 4. Detach/Unlink the Disk from the VM

To safely remove a passthrough disk from the VM:

1. Power off the VM.
2. Run:

```
qm disk unlink <VMID> --idlist <scsiX>
```

Example:

```
qm disk unlink 101 --idlist scsi1
```

This removes the disk reference from the VM configuration.


## Design Considerations

Physical disks are passed directly to the TrueNAS VM as whole devices rather than individual partitions. This ensures full ZFS control, preserves SMART monitoring, and maintains accurate disk health visibility within the storage layer.

Direct passthrough is preferred over host-managed storage because TrueNAS is responsible for filesystem integrity and storage abstraction. Kubernetes consumes storage over the network (NFS/SMB), not as block devices, reinforcing a clear separation between the hypervisor, the storage backend, and the application platform.

This approach also maintains a strict separation between the hypervisor (compute), the storage backend (TrueNAS), and the application platform (Kubernetes). In the future, the TrueNAS instance can be migrated to dedicated hardware with additional disks, enabling RAID configurations, improved redundancy, and a more structured backup strategy without changing how the cluster consumes storage.
