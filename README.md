# **virt-install-cloud**

Bash scripts and templates to **create, deploy, and remove cloud-init-enabled virtual machines**
using `virt-install`. It has been tested on **Ubuntu 26.04 LTS** and works
on other recent Ubuntu/Debian systems with a proper libvirt setup.

---

## **Requirements**

### **Install Required Packages (Ubuntu)**

```bash
sudo apt update
sudo apt install libvirt-daemon-system libvirt-clients qemu-kvm qemu-utils virtinst wget
```

For non-root usage, add your user to the `libvirt` and `kvm` groups:

```bash
sudo usermod -aG libvirt,kvm $USER
```

### **Required Tools (Local or Remote)**

These commands must be available on the host where you run the scripts (local system or the remote hypervisor when using `LIBVIRT_DEFAULT_URI`):

- `virsh`
- `virt-install`
- `wget`

---

## **Configuration**

### **Templates**

Example templates are provided in the `templates` directory:

- `cloud-config.yml-example`
- `launch-vm.ini-example`

To set up your configuration:

```bash
cp templates/cloud-config.yml-example templates/cloud-config.yml
cp templates/launch-vm.ini-example templates/launch-vm.ini
```

Edit:

- **`launch-vm.ini`** to configure network, CPUs, RAM, storage pool, etc.
- **`cloud-config.yml`** to define the default user, password, and SSH key.

### **Generate a password hash**

Use the helper script to create a SHA-512 hash for the `passwd:` field in `cloud-config.yml`:

```bash
bin/gen-passwd-hash.sh
```

Or from stdin (raw hash only):

```bash
echo 'secret' | bin/gen-passwd-hash.sh --stdin --raw
```

### **Adding New Distributions**

To support additional distributions, create an INI file in `templates/` (e.g., `debian12.ini`) with:

```ini
SOURCE=source-debian12.img
URL=https://cloud.debian.org/images/cloud/bookworm/daily/latest/debian-12-generic-amd64-daily.qcow2
OSVARIANT=debian12
VMPOOL=vm-pool
CONSOLE="pty,target_type=virtio"
```

---

## **Storage Pool Setup**

This script **stores base images and cloned VMs** in a libvirt storage pool (`vm-pool` by default). Create it if it doesn't exist:

```bash
virsh pool-define-as vm-pool dir - - - - "/var/lib/libvirt/images/vms"
virsh pool-build vm-pool
virsh pool-start vm-pool
virsh pool-autostart vm-pool
```

---

## **Creating a Virtual Machine**

```bash
./bin/launch-vm.sh -d ubuntu22.04 -n MyUbuntuVM -c 2 -m 2048 -s 32 -a 50 -N isolated
```

- **`-d ubuntu22.04`** → Uses `templates/ubuntu22.04.ini`
- **`-n MyUbuntuVM`** → VM name
- **`-c 2`** → CPUs
- **`-m 2048`** → Memory (MB)
- **`-s 32`** → Disk size (GB)
- **`-a 50`** → Additional data disk size (GB)
- **`-N isolated`** → Secondary NIC attached to libvirt network `isolated`
- **`-f`** → Force a fresh download of the base image even if it already exists
- **`-r`** → Recreate: destroy an existing VM of the same name and its volumes, then rebuild

### **Deploying to a Remote Hypervisor**

Set the `LIBVIRT_DEFAULT_URI` environment variable:

```bash
export LIBVIRT_DEFAULT_URI="qemu+ssh://user@hypervisor/system"
```

---

## **Removing a Virtual Machine**

```bash
bin/remove-vm.sh -d <VM_NAME>
```

---

## **Deleting a Base Image**

```bash
virsh vol-delete --pool vm-pool --vol source-ubuntu22.04.img
```

The next VM deployment will download a fresh image.

---

## **Inspecting VMs**

### **List running VMs and their IP addresses**

```bash
bin/list-vm-ips.sh
```

Prints a table of running VMs with their state, hostname (`<name>.<DOMAIN>`), and
DHCP-leased IP address on the primary network. VMs without a lease yet show
`pending`.

### **Diagnose networking for a VM**

```bash
bin/diagnose-vm-network.sh <vm-name> [vm-name ...]
```

Shows, per VM, how libvirt can discover its networking: domain state, whether the
QEMU guest agent responds, the interface list (`domiflist`), guest-reported
addresses (`domifaddr`), and matching DHCP leases on the primary network.

---

## **Local VM Name Resolution**

To resolve VM hostnames locally:

1. Install `libnss-libvirt`:

   ```bash
   sudo apt install libnss-libvirt
   ```

2. Edit `/etc/nsswitch.conf`, adding `libvirt libvirt_guest` to the `hosts` line:

   ```txt
   hosts: files libvirt libvirt_guest dns
   ```

Now you can SSH to VMs using their hostname.

---

## **Overriding Defaults**

### **Use a custom `launch-vm.ini`**

```bash
export LAUNCH_VM_INI="/path/to/custom-launch-vm.ini"
./launch-vm.sh -d ubuntu22.04 -n test-vm
```

> Uses `/path/to/custom-launch-vm.ini` instead of `templates/launch-vm.ini`.

### **Use a custom cloud-init file**

```bash
export CLOUD_CONFIG="/custom/path/cloud-config.yml"
./launch-vm.sh -d ubuntu22.04 -n test-vm
```

> Uses `/custom/path/cloud-config.yml` instead of `templates/cloud-config.yml`.

### **Use a specific Python interpreter for `virt-install`**

```bash
export PYTHON="/usr/bin/python3.12"
./launch-vm.sh -d ubuntu22.04 -n test-vm
```

> `virt-install` is run under `${PYTHON:-/usr/bin/python3}`. Set `PYTHON` if the
> `python3` first on your `PATH` (e.g. a Homebrew/pyenv one) lacks the system
> `gi`/`libvirt` bindings and fails with `ModuleNotFoundError: No module named 'gi'`.

---

## **Contributors**

- **rotflol (Ronald Offerman)** – Testing and contributions.
- **Steve Arnold**
