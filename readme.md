# virt-install-cloud

## What is this all about

It is a collection of bashs script easily setup and destroy cloud init enabled virtual machines locally.

Actively being used on:

- Ubuntu 20.04 LTS
- Ubuntu 22.04 LTS

## Required packages (Ubuntu)

- cloud-image-utils

## Configuration

@TODO

## Example of creating a new virtual machine

```bash
sudo ./launch-vm.sh  -d centos8 -c 2 -m 2048 -s 32 -n CentOS-8
```

## Resolving libvirt machines locally

Install the libnss-libvirt package.

In /etc/nsswitch.conf after files add ``libvirt libvirt_guest``

After this you should be able to ping and ssh to your virtual machine based on their name.

## Additional useful information

### Useful commands

```bash
- virt-resize --expand /dev/sda1 centos8-org.img centos8.img
- virt-filesystems --long -h --all -a centos8.img
- virsh net-dhcp-leases default
```

### Loopback mounting qcow2 images

```bash
modprobe nbd max_part=63
qemu-nbd -c /dev/nbd0 disk.img
mount /dev/nbd0p1 /mnt/disk
umount /mnt/disk
qemu-nbd -d /dev/nbd0
```

## Thanks to our contributors

- rotflol (Ronald Offerman)
