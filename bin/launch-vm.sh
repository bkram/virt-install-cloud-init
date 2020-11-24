#!/bin/bash
# (c) 2020 Mark de Bruijn <mrdebruijn@gmail.com>
# Deploy cloud image to local libvirt, with a cloud init configuration
VER="1.2.0 (20201124)"
SCRIPTHOME="$(dirname $(dirname $(realpath "$0")))"

if [ -e "${SCRIPTHOME}/launch-vm.ini" ]; then
    source "${SCRIPTHOME}/launch-vm.ini"
elif [ -e "${SCRIPTHOME}/templates/launch-vm.ini" ]; then
    source "${SCRIPTHOME}/templates/launch-vm.ini"
elif [ -e /usr/local/etc/launch-vm.ini ]; then
    source /usr/local/etc/launch-vm.ini
elif [ -e ~/.local/launch-vm.ini ]; then
    source ~/.local/launch-vm.ini
elif [ -e /etc/launch-vm.ini ]; then
    source /etc/launch-vm.ini
else
    NETWORK=default
    DOMAIN=lan
    VCPUS=2
    VMEM=2048
    LVTEMPLATES=${SCRIPTHOME}/templates
    LVIMAGES=${SCRIPTHOME}/images
    LVCLOUD=${LVIMAGES}
    LVVMS=${LVIMAGES}
    LVSEED=${LVIMAGES}
fi

function usage() {
    echo "Usage: $(basename "$0") [-d distribution] [-n name] [-f] [-c vcpu] [-m memory] [-s disk] [-S disksize] [-t cloudinit file]" 2>&1
    echo 'Deploy cloud image to local libvirt, with a cloud init configuration'
    echo '   -d     Distribution name'
    echo '   -n     VM Name'
    echo '   -c     Amount of vcpus'
    echo '   -m     Amount of memory in MB'
    echo '   -s     reSize the disk to GB'
    echo '   -t     Alternative cloud-init config.yml'
    echo '   -f     Fetch cloud image, overwrite when image already exists'
    echo '   -v     show version'
    exit 1
}

# if no input argument found, exit the script with usage
if [[ ${#} -eq 0 ]]; then
    usage
fi

# Define list of arguments expected in the input
optstring="d:n:c:m:s:ft:vh"

while getopts ${optstring} arg; do
    case ${arg} in
    d)
        DISTRIBUTION="${OPTARG}"
        ;;
    n)
        VMNAME="${OPTARG}"
        ;;
    c)
        VCPUS="${OPTARG}"
        ;;
    m)
        VMEM="${OPTARG}"
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

if [ -e "${LVTEMPLATES}/${DISTRIBUTION}.ini" ]; then
    source "${LVTEMPLATES}/${DISTRIBUTION}.ini"
else
    echo "Distribution template ${DISTRIBUTION}.ini not found"
    exit 1
fi

source-image() {
    if [[ ${FETCH} == true ]]; then
        wget "${URL}" -O "${LVCLOUD}/${SOURCE}"
    fi
    if [ ! -e "${LVCLOUD}/${SOURCE}" ]; then
        echo Source image "${SOURCE}" not detected on disk, You can enable a download with -f
        exit 1
    fi
}

resize-disk() {
    VMDISK=vm-${VMNAME}
    cp "${LVCLOUD}/${SOURCE}" "${LVVMS}/${VMDISK}.img"
    if [[ ${SIZE} -gt 0 ]]; then
        qemu-img resize "${LVVMS}/${VMDISK}.img" "${ABSSIZE}"G
    fi
}

prep-seed() {
    if [[ -z "${TEMPLATE}" ]]; then
        TEMPLATE=cloud-config.yml
    else
        if [ ! -e "${LVTEMPLATES}/${TEMPLATE}" ]; then
            echo Template ${TEMPLATE} not detected on disk.
            exit 1
        fi
    fi
    cloud-localds -v "${LVSEED}/${VMNAME}.iso" "${LVTEMPLATES}/${TEMPLATE}"
}

vm-setup() {
    virt-install \
        --name "${VMNAME}" \
        --memory "${VMEM}" \
        --vcpus "${VCPUS}" \
        --disk "${LVVMS}/${VMDISK}.img",device=disk,bus=virtio \
        --disk "${LVSEED}/${VMNAME}.iso",device=cdrom \
        --os-variant "${OSVARIANT}" \
        --network network="${NETWORK}",model=virtio \
        --virt-type kvm \
        --import \
        --qemu-commandline='-smbios type=1,serial=ds=nocloud;h='"${VMNAME}"'.'"${DOMAIN}"'' \
        --console "${CONSOLE}" \
        --video none \
        --graphics none

    virsh detach-disk --domain "${VMNAME}" "$(virsh dumpxml --domain "$VMNAME" | xmllint --xpath "/domain/devices/disk/source/@file" - | cut -f 2-2 -d\" | grep -E iso\$)" --persistent --config
    rm "${LVSEED}/${VMNAME}.iso"
    virsh start --domain "${VMNAME}"
    virsh domifaddr --domain "${VMNAME}"
}

source-image
resize-disk
prep-seed
vm-setup
