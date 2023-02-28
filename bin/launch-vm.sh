#!/bin/bash
# (c) 2020 Mark de Bruijn <mrdebruijn@gmail.com>
# Deploy cloud image to local libvirt, with a cloud init configuration
VER="1.3.0 (20230228)"

# shellcheck disable=SC2046
SCRIPTHOME="$(dirname $(dirname $(realpath "$0")))"

if [ -e "${SCRIPTHOME}/launch-vm.ini" ]; then
    # shellcheck source=/dev/null
    source "${SCRIPTHOME}/launch-vm.ini"
elif [ -e "${SCRIPTHOME}/templates/launch-vm.ini" ]; then
    # shellcheck source=/dev/null
    source "${SCRIPTHOME}/templates/launch-vm.ini"
elif [ -e /usr/local/etc/launch-vm.ini ]; then
    # shellcheck source=/dev/null
    source /usr/local/etc/launch-vm.ini
elif [ -e ~/.local/launch-vm.ini ]; then
    # shellcheck source=/dev/null
    source ~/.local/launch-vm.ini
elif [ -e /etc/launch-vm.ini ]; then
    # shellcheck disable=SC1091
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
    echo "Usage: $(basename "$0") [-d distribution] [-n VM name] [-f] [-c vcpu] [-m memory] [-s disksize] [-t cloudinit file] [-e network-config-v1 file]" 2>&1
    echo 'Deploy cloud image to local libvirt, with a cloud init configuration'
    echo '   -d     Distribution name'
    echo '   -n     VM Name'
    echo '   -c     Amount of vcpus'
    echo '   -m     Amount of memory in MB'
    echo '   -s     reSize the disk to GB'
    echo '   -t     Alternative cloud-init config yml'
    echo '   -e     Cloud-init network-config-v1 yml'
    echo '   -f     Fetch cloud image, overwrite when image already exists'
    echo '   -v     show version'
    exit 1
}

# if no input argument found, exit the script with usage
if [[ ${#} -eq 0 ]]; then
    usage
fi

# Define list of arguments expected in the input
optstring="d:n:c:m:s:fte:vh"

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
    e)
        NETCONFIG="${OPTARG}"
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

if [[ ${USAGE} == true ]] || [[ -z ${VMNAME} ]]; then
    usage
fi

if [ -e "${LVTEMPLATES}/${DISTRIBUTION}.ini" ]; then
    # shellcheck source=/dev/null
    source "${LVTEMPLATES}/${DISTRIBUTION}.ini"
else
    echo "Distribution template ${DISTRIBUTION}.ini not found"
    exit 1
fi

verify-sudo() {
    if [ "$UID" -ne "0" ]; then
        echo "Use sudo to run this command."
        exit 1
    fi
}

verify-commands() {
    for command in virsh virt-install cloud-localds qemu-img wget xmllint; do
        if ! which ${command} >/dev/null; then
            echo "Missing command '${command}', please install command and try again."
            exit 1
        fi
    done
}

verify-folders() {
    for folder in "${LVCLOUD}" "${LVVMS}" "${LVSEED}"; do
        if [ ! -d "${folder}" ]; then
            echo "Directory '${folder}' is missing, please create it and try again."
            exit 1
        fi
    done
}

source-image() {
    if [[ "${FETCH}" == "true" ]]; then
        wget "${URL}" -O "${LVCLOUD}/${SOURCE}"
    fi
    if [ ! -e "${LVCLOUD}/${SOURCE}" ]; then
        echo "Source image '${LVCLOUD}/${SOURCE}' not detected on disk, You can force a download with -f"
        exit 1
    fi
}

prep-disk() {
    VMDISK=vm-${VMNAME}
    cp "${LVCLOUD}/${SOURCE}" "${LVVMS}/${VMDISK}.img"
    if [[ ${SIZE} -gt 0 ]]; then
        qemu-img resize "${LVVMS}/${VMDISK}.img" "${SIZE}"G
    fi
}

prep-seed() {
    if [[ -z "${TEMPLATE}" ]]; then
        TEMPLATE=cloud-config.yml
    else
        if [ ! -e "${LVTEMPLATES}/${TEMPLATE}" ]; then
            echo Template "${TEMPLATE}" not detected on disk.
            exit 1
        fi
    fi
    if [ ! -e "${LVTEMPLATES}/${TEMPLATE}" ]; then
        echo Template "${TEMPLATE}" not detected on disk.
        exit 1
    fi

    if [ -n "${NETCONFIG}" ]; then
        cloud-localds -v --network-config="${LVTEMPLATES}/${NETCONFIG}" "${LVSEED}/${VMNAME}.iso" "${LVTEMPLATES}/${TEMPLATE}"
    else
        cloud-localds -v "${LVSEED}/${VMNAME}.iso" "${LVTEMPLATES}/${TEMPLATE}"
    fi

}

verify-exist() {
    if virsh dominfo --domain "${VMNAME}" >/dev/null 2>&1; then
        echo "Error the VM '${VMNAME}' already exists."
        exit 1
    fi
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
        --wait \
        --noautoconsole \
        --video none \
        --console "${CONSOLE}"

    virsh change-media --domain "${VMNAME}" "$(virsh dumpxml --domain "${VMNAME}" | xmllint --xpath "/domain/devices/disk/source/@file" - | cut -f 2-2 -d\" | grep -E iso\$)" --eject --force --config
    rm "${LVSEED}/${VMNAME}.iso"
    virsh start --domain "${VMNAME}"

    if [[ "${NETWORK}" == "default" ]]; then
        echo "Waiting for VM to start in order to retrieve ip address (domifaddr), when using default network only."
        sleep 10
        virsh domifaddr --domain "${VMNAME}"
    fi
}

verify-sudo
verify-commands
verify-folders
verify-exist
source-image
prep-disk
prep-seed
vm-setup
