#!/bin/bash
wget https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64-disk-kvm.img -O ubuntu-source.img

virsh destroy --domain ubuntu20-cloud
virsh undefine --domain ubuntu20-cloud --remove-all-storage

cp ubuntu-source.img ubuntu20.img
qemu-img resize ubuntu20.img +32G

sudo cloud-localds -v cloud-init.iso cloud-config-libvirt.yml #--network-config network.yml

sudo virt-install \
            --name ubuntu20-cloud \
            --memory 4096 \
            --vcpus 4 \
            --disk ubuntu20.img,device=disk,bus=virtio \
            --disk cloud-init.iso,device=disk,bus=virtio \
            --os-variant ubuntu20.04 \
            --network network=default,model=virtio \
            --virt-type kvm \
            --import \
            --console pty,target_type=virtio \
            --noautoconsole \
