#!/bin/bash
# wget "https://cloud.centos.org/centos/8/x86_64/images/CentOS-8-GenericCloud-8.2.2004-20200611.2.x86_64.qcow2"

virsh destroy --domain centos8-cloud
virsh undefine --domain centos8-cloud --remove-all-storage

cp CentOS-8-GenericCloud-8.2.2004-20200611.2.x86_64.qcow2 centos8.img
qemu-img resize centos8.img +22G

sudo cloud-localds -v cloud-init.iso cloud-config-libvirt.yml

sudo virt-install \
            --name centos8-cloud \
            --memory 4096 \
            --vcpus 4 \
            --disk centos8.img,device=disk,bus=virtio \
            --disk cloud-init.iso,device=cdrom \
            --os-variant centos8 \
            --network network=default,model=virtio \
            --virt-type kvm \
            --import \
            --console pty,target_type=virtio \
            --noautoconsole
