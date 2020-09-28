#!/bin/bash
VMNAME=$1
URL=https://cloud.centos.org/centos/8/x86_64/images/CentOS-8-GenericCloud-8.2.2004-20200611.2.x86_64.qcow2
SOURCE=source-centos8.img
OSVARIANT=centos8

# wget $URL -O ../images/$SOURCE

cp ../images/$SOURCE ../images/$VMNAME.img
qemu-img resize ../images/$VMNAME.img +32G

cloud-localds -v ../images/seed-$VMNAME.iso ../templates/cloud-config-libvirt.yml

virt-install \
    --name $VMNAME \
    --memory 4096 \
    --vcpus 4 \
    --disk ../images/$VMNAME.img,device=disk,bus=virtio \
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
