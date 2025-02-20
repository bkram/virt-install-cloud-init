# virt-install-cloud

This repository provides bash scripts to easily create, deploy and destroy cloud‑init–enabled virtual machines using virt-install. It has been tested on Ubuntu 24.04 LTS (development) and works on other recent Ubuntu/Debian systems with proper libvirt configuration.

## Required Packages (Ubuntu)

Install at minimum:

```bash
sudo apt update
sudo apt install libvirt-daemon-system libvirt-clients qemu-kvm virtinst wget cloud-image-utils
```

*(Add your user to the `libvirt` and `kvm` groups for non‑sudo usage of the scripts.)*

## Configuration

### Provided Templates

The repository includes example templates in the `templates` directory:

- `cloud-config.yml-example`
- `launch-vm.ini-example`

To configure, copy these files:

```bash
cp templates/cloud-config.yml-example templates/cloud-config.yml
cp templates/launch-vm.ini-example templates/launch-vm.ini
```

Then edit:

- **`launch-vm.ini`** to match your libvirt settings (network, default memory/CPUs, storage pool name, etc.).
- **`cloud-config.yml`** to add your username, password (if desired), and SSH public key.

### Adding Additional Templates

To support additional distributions, create a new INI file in the `templates/` directory with a name matching the distribution (e.g., `debian12.ini`). In the new INI file, define at least the following keys:

- **`SOURCE`**: The name for the base image volume (e.g., `source-debian12.img`).
- **`URL`**: The cloud image download URL.
- **`OSVARIANT`**: The OS variant (e.g., `debian12`).
- **`VMPOOL`**: (Optional) The storage pool name (default is `vm-pool`).
- **`CONSOLE`**: (Optional) Console settings (e.g., `pty,target_type=virtio`).

Example `debian12.ini`:

```ini
SOURCE=source-debian12.img
URL=https://cloud.debian.org/images/cloud/bookworm/daily/latest/debian-12-generic-amd64-daily.qcow2
OSVARIANT=debian12
VMPOOL=vm-pool
CONSOLE="pty,target_type=virtio"
```

## Storage Pool Setup

Our script uses a single libvirt storage pool (default: `vm-pool`) to store both base images and cloned VM disks. Create the pool on your hypervisor if it doesn’t exist:

```bash
virsh pool-define-as vm-pool dir - - - - "/var/lib/libvirt/images/vms"
virsh pool-build vm-pool
virsh pool-start vm-pool
virsh pool-autostart vm-pool
```

**Adjust the directory as needed.**

## Creating a New Virtual Machine

Assuming you have a distribution INI (for example, `ubuntu22.04.ini`) in your `templates/` directory, run:

```bash
./bin/launch-vm.sh -d ubuntu22.04 -n MyUbuntuVM -c 2 -m 2048 -s 32
```

- **`-d ubuntu22.04`** selects `templates/ubuntu22.04.ini`.
- **`-n MyUbuntuVM`** is the new VM name.
- **`-c 2`** sets 2 CPUs.
- **`-m 2048`** allocates 2GB of RAM.
- **`-s 32`** resizes the cloned disk to 32GB.

### Remote Hypervisor

To target a remote hypervisor, export the connection URI:

```bash
export LIBVIRT_DEFAULT_URI="qemu+ssh://user@hypervisor/system"
```

Make sure you have the proper user setup on the hypervisor, if not run the code below on the hypervisor.

```bash
sudo usermod -aG libvirt,kvm $USER
```

## Deleting a Virtual Machine

```bash
bin/remove.vm -d <virtual-machine>
```

## Deleting a Base Image

To force a re-download or upgrade the base image:

```bash
virsh vol-delete --pool vm-pool --vol source-ubuntu22.04.img
```

The next run of the script will download a fresh copy.

## Local Resolution of Virtual Machines

To resolve your locally running virtual machines by hostname on your local system:

1. **Install `libnss-libvirt`:**

   ```bash
   sudo apt install libnss-libvirt
   ```

2. **Edit `/etc/nsswitch.conf`:**
   Add `libvirt libvirt_guest` to the `hosts` line. For example:

   ```text
   hosts: files libvirt libvirt_guest dns
   ```

3. Now you can ping or SSH to your VMs by their hostname (as defined in `launch-vm.ini`).

## Contributors

- **rotflol (Ronald Offerman)** for testing and contributions.
