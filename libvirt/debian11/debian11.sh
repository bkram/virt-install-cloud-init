#!/bin/bash
wget https://cloud.debian.org/images/cloud/bullseye/daily/20200924-401/debian-11-generic-amd64-daily-20200924-401.qcow2 -O debian-source.img

virsh destroy --domain debian11-cloud
virsh undefine --domain debian11-cloud --remove-all-storage

cp debian-source.img debian11.img
qemu-img resize debian11.img +30G

sudo cloud-localds -v cloud-init.iso cloud-config-libvirt.yml #--network-config network.yml

sudo virt-install \
            --name debian11-cloud \
            --memory 4096 \
            --vcpus 4 \
            --disk debian11.img,device=disk,bus=virtio \
            --disk cloud-init.iso,device=cdrom \
            --os-variant debian10 \
            --network network=default,model=virtio \
            --virt-type kvm \
            --import \
            --console pty,target_type=serial \
            --noautoconsole \
