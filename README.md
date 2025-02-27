# **virt-install-cloud**

This repository provides Bash scripts to **create, deploy, and remove cloud-init-enabled virtual machines** using `virt-install`. It has been tested on **Ubuntu 24.04 LTS** and works on other recent Ubuntu/Debian systems with a proper libvirt setup.

---

## **Requirements**

### **Install Required Packages (Ubuntu)**

```bash
sudo apt update
sudo apt install libvirt-daemon-system libvirt-clients qemu-kvm virtinst wget cloud-image-utils
```

For non-root usage, add your user to the `libvirt` and `kvm` groups:

```bash
sudo usermod -aG libvirt,kvm $USER
```

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
./bin/launch-vm.sh -d ubuntu22.04 -n MyUbuntuVM -c 2 -m 2048 -s 32
```

- **`-d ubuntu22.04`** → Uses `templates/ubuntu22.04.ini`
- **`-n MyUbuntuVM`** → VM name
- **`-c 2`** → CPUs
- **`-m 2048`** → Memory (MB)
- **`-s 32`** → Disk size (GB)

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

## **Local VM Name Resolution**

To resolve VM hostnames locally:

1. Install `libnss-libvirt`:

   ```bash
   sudo apt install libnss-libvirt
   ```

2. Edit `/etc/nsswitch.conf`, adding `libvirt libvirt_guest` to the `hosts` line:

   ```
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

---

## **Contributors**

- **rotflol (Ronald Offerman)** – Testing and contributions.
