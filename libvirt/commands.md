# Useful Commands

- virt-resize --expand /dev/sda1 centos8-org.img centos8.img
- virt-filesystems --long -h --all -a centos8.img
- virsh destroy --domain $VMNAME
- virsh shutdown --domain $VMNAME
- virsh undefine --domain $VMNAME --remove-all-storage
- virsh net-dhcp-leases default

## Loopback mounting qcow2 images

modprobe nbd max_part=63
qemu-nbd -c /dev/nbd0 disk1.qcow2
qemu-nbd -c /dev/nbd0 centos-source.img
mount /dev/nbd0p1 /media/
qemu-nbd -d /dev/nbd0

## example usage
sudo ./launch-vm.sh -d centos8 -c 2 -m 2048 -s 32 -t cloud-config-libvirt.yml -n CentOS-8
sudo virsh domifaddr CentOS-8

mrk@kvm:~/cloud-init/libvirt/ubuntu20$ xmllint --xpath "/domain/devices/disk/source/@file" yr.xml 

