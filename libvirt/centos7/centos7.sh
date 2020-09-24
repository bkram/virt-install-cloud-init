#!/bin/bash
wget https://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud-2003.qcow2 -O centos-source.img

virsh destroy --domain centos7-cloud
virsh undefine --domain centos7-cloud --remove-all-storage

cp centos-source.img centos7.img
qemu-img resize centos7.img +22G

sudo cloud-localds -v cloud-init.iso cloud-config-libvirt.yml

sudo virt-install \
            --name centos7-cloud \
            --memory 4096 \
            --vcpus 4 \
            --disk centos7.img,device=disk,bus=virtio \
            --disk cloud-init.iso,device=cdrom \
            --os-variant centos7.0 \
            --network network=default,model=virtio \
            --virt-type kvm \
            --import \
            --console pty,target_type=virtio \
            --noautoconsole
