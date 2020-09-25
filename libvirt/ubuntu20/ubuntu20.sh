#!/bin/bash
VMNAME=$1

# wget https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64-disk-kvm.img -O ../images/source-ubuntu20.04.img

cp ../images/source-ubuntu20.04.img ../images/$VMNAME.img
qemu-img resize ../images/$VMNAME.img +32G

cat cloud-config-libvirt.yml | sed s/'{{ hostname }}'/$VMNAME/g > seed-$VMNAME.yml

rm -f ../images/seed-$VMNAME.iso
cloud-localds -v ../images/seed-$VMNAME.iso seed-$VMNAME.yml
rm seed-$VMNAME.yml

virt-install \
    --name $VMNAME \
    --memory 4096 \
    --vcpus 4 \
    --disk ../images/$VMNAME.img,device=disk,bus=virtio \
    --disk ../images/seed-$VMNAME.iso,device=disk,bus=virtio \
    --os-variant ubuntu20.04 \
    --network network=default,model=virtio \
    --virt-type kvm \
    --import \
    --console pty,target_type=virtio \
    --noautoconsole \
