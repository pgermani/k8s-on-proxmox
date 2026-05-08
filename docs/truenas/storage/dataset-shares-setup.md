# Dataset and Shares Setup (TrueNAS SCALE)

Below is how datasets and network shares are configured in TrueNAS SCALE for this homelab.

TrueNAS acts as the storage backend of the Kubernetes platform, exposing:

- **NFS** for dynamic provisioning of Kubernetes workloads
- **SMB** for media storage and application configuration access

All configuration was performed through the TrueNAS SCALE Web UI.

## 1. Storage Pool Creation

In this setup, two separate pools are created, each backed by a **single disk**. Since only two disks are available, no RAID configuration is used at this stage.

### Steps

1. Navigate to **Storage**
2. Click **Create Pool**
3. Create a new pool:
   - Select the available disk
   - Layout: **Stripe**
   - Use **one disk per pool**
4. Repeat the process for the second disk to create the second pool.

> Each pool in this setup is backed by a single disk and therefore provides **no redundancy**.

## 2. Dataset Creation

After creating the storage pools, datasets must be created to organize storage within each pool.
In this setup, two datasets are created for each pool. The naming convention can be adapted based on the intended usage.

Example structure:

```
<pool-name>/
    volumes/
    data/
```
### Steps
1. Navigate to **Datasets**
2. Expand the desired pool.
3. Click **Add Dataset**.
4. Create the required datasets (e.g. `volumes`, `data`).
5. Repeat the process for the other pool.

## 3. NFS Share Configuration

### 3.1 Create the NFS Share

1. Navigate to **Shares -> UNIX (NFS) Shares**
2. Click **Add**
3. Configure the share:

- **Path**: select the dataset path (example: `/mnt/crucial/volumes`)
- **Maproot User**: `root`
- **Authorized Hosts**: add the IP addresses of the Kubernetes nodes

> Using `root` as the maproot user avoids permission issues when Kubernetes creates subdirectories through the NFS provisioner.

> During testing you can temporarily add your workstation IP to verify NFS mounts. Remove it afterwards if not required.

This dataset will be used by the `nfs-subdir-external-provisioner` running inside the Kubernetes cluster.

### 3.2 Enable the NFS Service

After creating the share, enable the NFS service.

1. Navigate to **System -> Services**
2. Enable **NFS**
3. Toggle **Start Automatically**

### 3.3 Testing the NFS Share (Optional)

Before integrating the share with Kubernetes, it can be useful to verify that the NFS service is reachable and that the export works correctly.

This test can be performed from any Linux machine on the same network, for example one of the Kubernetes node VMs.

Example test on Linux:

```
mkdir ~/nfs-test

sudo mount -v -t nfs -o vers=4,port=2049 <TRUENAS-IP>:<DATASET-PATH> ~/nfs-test

ls ~/nfs-test

sudo umount ~/nfs-test
rm -rf ~/nfs-test
```

If the mount succeeds, the NFS share is correctly exported and ready to be consumed by Kubernetes.

## 4. Creating SMB Share

### 4.1 Create a Dedicated SMB User

Before creating the SMB share, create a user that will be used to authenticate against the share.

1. Navigate to **Credentials -> Users**
2. Click **Add**
3. Configure:

- **Username**: example `smb-user`
- **Full Name**: example `smb-user`
- **Password**: strong password
- **Auxiliary Groups**: builtin_administrators
- **SMB User**: enabled

This user will later be used by Kubernetes (via the SMB CSI driver) to authenticate when mounting the share.

### 4.2 Create the SMB Share

1. Navigate to **Shares -> Windows (SMB) Shares**
2. Click **Add**
3. Configure the share:

- **Path**: select the dataset path (example: `/mnt/kingSpec/data`)
- **Name**: share name (example `data`)
- **Purpose**: default

This share will be used for workloads that require direct file access or media storage.

### 4.3 Enable the SMB Service

After creating the share, enable the SMB service.

1. Navigate to **System -> Services**
2. Enable **SMB**
3. Toggle **Start Automatically**

### 4.4 Testing the SMB Share (Optional)

Before integrating the share with Kubernetes or other services, it can be useful to verify that the SMB share is accessible from the network.

From any desktop machine on the same network, open the file browser and connect to:

```
smb://<TRUENAS-IP>/<SHARE-NAME>
```

Authenticate using the SMB user created earlier.

If the configuration is correct, the available shares should be visible and accessible.