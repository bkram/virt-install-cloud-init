#!/bin/bash
VMNAME=$1
VMDISK=vm-$1
URL=https://cloud-images.ubuntu.com/groovy/current/groovy-server-cloudimg-amd64-disk-kvm.img
SOURCE=source-ubuntu20.10.img
OSVARIANT=ubuntu20.04

# wget $URL -O ../images/$SOURCE

cp ../images/$SOURCE ../images/$VMDISK.img
qemu-img resize ../images/$VMDISK.img +32G

cloud-localds -v ../images/seed-$VMNAME.iso ../templates/cloud-config-libvirt.yml

virt-install \
    --name $VMNAME \
    --memory 4096 \
    --vcpus 4 \
    --disk ../images/$VMDISK.img,device=disk,bus=virtio \
    --disk ../images/seed-$VMNAME.iso,device=cdrom \
    --os-variant $OSVARIANT \
    --network network=default,model=virtio \
    --virt-type kvm \
    --import \
    --qemu-commandline='-smbios type=1,serial=ds=nocloud;h='$VMNAME'.ttl' \
    --console pty,target_type=virtio \
    --video none

virsh detach-disk --domain $VMNAME $(virsh dumpxml --domain $VMNAME | xmllint --xpath "/domain/devices/disk/source/@file" - | cut -f 2-2 -d\" | egrep iso\$) --persistent --config
rm -f ../images/seed-$VMNAME.iso
virsh start --domain $VMNAME
