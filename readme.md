# virt-install-cloud

## What is this all about

It is a bash to script easily setup cloud init virtual machines with virt install (for lab purposes).

## Example usage

```bash
sudo ./launch-vm.sh  -d centos8 -c 2 -m 2048 -s 32 -n CentOS-8
```

## Configuration

@TODO

## Additional useful Commands

```bash
- virt-resize --expand /dev/sda1 centos8-org.img centos8.img
- virt-filesystems --long -h --all -a centos8.img
- virsh destroy --domain $VMNAME
- virsh shutdown --domain $VMNAME
- virsh undefine --domain $VMNAME --remove-all-storage
- virsh net-dhcp-leases default
```

## Loopback mounting qcow2 images

```bash
modprobe nbd max_part=63
qemu-nbd -c /dev/nbd0 disk1.qcow2
qemu-nbd -c /dev/nbd0 centos-source.img
mount /dev/nbd0p1 /media/
qemu-nbd -d /dev/nbd0
```

## Thanks to our contributors

- rotflol (Ronald Offerman)

## Required packages (Ubuntu)

- cloud-image-utils
