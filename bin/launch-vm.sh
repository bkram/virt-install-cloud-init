#!/bin/bash
# (c) 2020 Mark de Bruijn <mrdebruijn@gmail.com>
# Deploy cloud image to local libvirt, with a cloud init configuration
VER="1.0.4 (20201121)"

function usage() {
    echo "Usage: $(basename $0) [-d distribution] [-n name] [-f] [-c vcpu] [-m memory] [-s disk] [-S disksize] [-t cloudinit file]" 2>&1
    echo 'Deploy cloud image to local libvirt, with a cloud init configuration'
    echo '   -d     Distribution name'
    echo '   -n     VM Name'
    echo '   -c     Amount of vcpus'
    echo '   -m     Amount of memory in MB'
    echo '   -s     Size to add to the disk in GB'
    echo '   -S     reSize the disk to GB'
    echo '   -t     Alternative cloud-init config.yml'
    echo '   -f     Fetch cloud image, even when image already exists'
    echo '   -v     show version'
    exit 1
}

# if no input argument found, exit the script with usage
if [[ ${#} -eq 0 ]]; then
    usage
fi

# Define list of arguments expected in the input
optstring="d:n:c:m:s:ft:S:vh"

while getopts ${optstring} arg; do
    case ${arg} in
        d)
            DISTRIBUTION="${OPTARG}"
            ;;
        n)
            VMNAME="${OPTARG}"
            ;;
        c)
            VCPUS="--vcpus ${OPTARG}"
            ;;
        m)
            VMEM="--memory ${OPTARG}"
            ;;
        f)
            FETCH='true'
            ;;
        s)
            SIZE="${OPTARG}"
            ;;
        v)
            SVER='true'
            ;;
        h)
            USAGE='true'
            ;;
        S)
            ABSSIZE="${OPTARG}"
            ;;
        t)
            TEMPLATE="${OPTARG}"
            ;;
        ?)
            echo "Invalid option: -${OPTARG}."
            echo
            usage
            ;;
    esac
done

if [[ ${SVER} == true ]]; then
  echo "${0} version: ${VER}"
  exit 0
fi

if [[ ${USAGE} == true ]]; then
  usage
  exit 0
fi

if [ -e ${SCRIPTHOME}/templates/settings.ini ]; then
    source ${SCRIPTHOME}/templates/settings.ini
else
    NETWORK=default
    DOMAIN=lan
fi

if [ -e ${SCRIPTHOME}/templates/${DISTRIBUTION}.ini ]; then
    source ${SCRIPTHOME}/templates/${DISTRIBUTION}.ini
else
    echo "Distribution template ${DISTRIBUTION}.ini not found"
    exit 1
fi

source-image() {
    if [[ ${FETCH} == true ]]; then
        wget ${URL} -O ${SCRIPTHOME}/images/${SOURCE}
    fi
    if [ ! -e ${SCRIPTHOME}/images/${SOURCE} ]; then
        echo Source image ${SOURCE} not detected on disk, You can enable a download with -f
        exit 1
    fi
}

prep-disk() {
    VMDISK=vm-${VMNAME}
    cp ${SCRIPTHOME}/images/${SOURCE} ${SCRIPTHOME}/images/${VMDISK}.img
    if [[ ${SIZE} -gt 0 ]]; then
        qemu-img resize ${SCRIPTHOME}/images/${VMDISK}.img +${SIZE}G
    fi
}

resize-disk() {
    VMDISK=vm-${VMNAME}
    cp ${SCRIPTHOME}/images/${SOURCE} ${SCRIPTHOME}/images/${VMDISK}.img
    if [[ ${ABSSIZE} -gt 0 ]]; then
        qemu-img resize ${SCRIPTHOME}/images/${VMDISK}.img ${SIZE}G
    fi
}

prep-seed() {
    if [[ -z "${TEMPLATE}" ]]; then
        TEMPLATE=cloud-config-virt.yml
    else
        if [ ! -e "${SCRIPTHOME}/templates/${TEMPLATE}" ]; then
            echo Template ${TEMPLATE} not detected on disk.
            exit 1
        fi
    fi
    cloud-localds -v ${SCRIPTHOME}/images/seed-${VMNAME}.iso ${SCRIPTHOME}/templates/${TEMPLATE}
}

vm-setup() {
    virt-install \
        --name ${VMNAME} \
        ${VMEM} \
        ${VCPUS} \
        --disk ${SCRIPTHOME}/images/${VMDISK}.img,device=disk,bus=virtio \
        --disk ${SCRIPTHOME}/images/seed-${VMNAME}.iso,device=cdrom \
        --os-variant ${OSVARIANT} \
        --network network=${NETWORK},model=virtio \
        --virt-type kvm \
        --import \
        --qemu-commandline='-smbios type=1,serial=ds=nocloud;h='${VMNAME}'.'${DOMAIN}'' \
        --console ${CONSOLE} \
        --video none

    virsh detach-disk --domain ${VMNAME} "$(virsh dumpxml --domain $VMNAME | xmllint --xpath "/domain/devices/disk/source/@file" - | cut -f 2-2 -d\" | grep -E iso\$)" --persistent --config
    rm -f ${SCRIPTHOME}/images/seed-${VMNAME}.iso
    virsh start --domain ${VMNAME}
    virsh domifaddr --domain ${VMNAME}
}

source-image
prep-disk
resize-disk
prep-seed
vm-setup
