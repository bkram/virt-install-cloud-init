#!/bin/bash
# (c) 2020 Mark de Bruijn <mrdebruijn@gmail.com>
# Deploy a cloud image to a libvirt-managed hypervisor

VER="1.10.0 (20260722)"

set -euo pipefail

# shellcheck disable=SC2046
SCRIPTHOME="$(dirname "$(dirname "$(realpath "$0")")")"

# Ensure LVTEMPLATES is always set before it is used
LVTEMPLATES="${SCRIPTHOME}/templates"

# -------------------------------------------------------------------------
# Load config from .ini or fall back to defaults
# -------------------------------------------------------------------------

if [[ -n "${LAUNCH_VM_INI:-}" && -e "${LAUNCH_VM_INI}" ]]; then
    echo "Using custom launch-vm.ini: ${LAUNCH_VM_INI}"
    # shellcheck source=/dev/null
    source "${LAUNCH_VM_INI}"
elif [ -e "${LVTEMPLATES}/launch-vm.ini" ]; then
    # shellcheck source=/dev/null
    source "${LVTEMPLATES}/launch-vm.ini"
else
    NETWORK=default
    DOMAIN=lan
    VCPUS=2
    VMEM=2048
    VMPOOL=vm-pool
fi

function usage() {
    echo "Usage: $(basename "$0") [options]"
    echo "Deploy a cloud image to a libvirt-managed hypervisor."
    echo
    echo "Options:"
    echo "  -d DISTRIB   Distribution name (e.g. 'ubuntu22.04')"
    echo "  -n NAME      VM Name"
    echo "  -c VCPUS     Number of CPUs (default: ${VCPUS})"
    echo "  -m MEM       Memory in MB (default: ${VMEM})"
    echo "  -s SIZE      Resize the cloned disk to SIZE GB (optional)"
    echo "  -a SIZE      Create an additional virtio disk of SIZE GB (optional)"
    echo "  -N NETWORK   Attach a secondary virtio NIC to libvirt network NETWORK (optional)"
    echo "  -f           Force a fresh download if the base volume already exists"
    echo "  -r           Recreate: destroy an existing VM and its volumes, then rebuild"
    echo "  -v           Show version and exit"
    echo
    exit 1
}

# -------------------------------------------------------------------------
# Parse arguments
# -------------------------------------------------------------------------
optstring="d:n:c:m:s:a:N:frvh"

FETCH=""
RECREATE=""
TMP_DIR=""

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
        s)
            SIZE="${OPTARG}"
            ;;
        a)
            EXTRA_SIZE="${OPTARG}"
            ;;
        N)
            SECONDARY_NETWORK="${OPTARG}"
            ;;
        f)
            FETCH='true'
            ;;
        r)
            RECREATE='true'
            ;;
        v)
            echo "$(basename "$0") version: ${VER}"
            exit 0
            ;;
        h)
            usage
            ;;
        ?)
            echo "Invalid option: -${OPTARG}."
            echo
            usage
            ;;
    esac
done

if [[ -z "${VMNAME:-}" || -z "${DISTRIBUTION:-}" ]]; then
    usage
fi

# -------------------------------------------------------------------------
# Load distribution-specific .ini
# -------------------------------------------------------------------------
if [ -e "${LVTEMPLATES}/${DISTRIBUTION}.ini" ]; then
    # shellcheck source=/dev/null
    source "${LVTEMPLATES}/${DISTRIBUTION}.ini"
else
    echo "Error: Distribution template '${DISTRIBUTION}.ini' not found in ${LVTEMPLATES}"
    exit 1
fi

# -------------------------------------------------------------------------
# Utility / Validation
# -------------------------------------------------------------------------
verify-commands() {
    for cmd in virsh virt-install wget; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            echo "Missing command '${cmd}'. Please install and try again."
            exit 1
        fi
    done
}

verify-pool() {
    if ! virsh pool-info "${VMPOOL}" >/dev/null 2>&1; then
        echo "Storage pool '${VMPOOL}' not found. Please create it or fix config."
        exit 1
    fi
}

verify-vm-not-exist() {
    if virsh dominfo --domain "${VMNAME}" >/dev/null 2>&1; then
        if [[ "${RECREATE}" == "true" ]]; then
            echo "Recreate: removing existing VM '${VMNAME}'..."
            virsh destroy --domain "${VMNAME}" >/dev/null 2>&1 || true
            virsh undefine --domain "${VMNAME}" --nvram >/dev/null 2>&1 \
                || virsh undefine --domain "${VMNAME}" >/dev/null 2>&1 || true
        else
            echo "Error: The VM '${VMNAME}' already exists."
            exit 1
        fi
    fi
}

delete-volume-if-exists() {
    local vol="$1"
    if virsh vol-info --pool "${VMPOOL}" --vol "${vol}" >/dev/null 2>&1; then
        echo "Recreate: deleting volume '${vol}'..."
        virsh vol-delete --pool "${VMPOOL}" --vol "${vol}"
    fi
}

base-volume-exists() {
    virsh vol-info --pool "${VMPOOL}" --vol "${SOURCE}" >/dev/null 2>&1
}

# -------------------------------------------------------------------------
# Fetch base image
# -------------------------------------------------------------------------
fetch-base-file() {
    TMP_DIR="$(mktemp -d -t cloudimg-XXXXXX)"
    TMP_CLOUD_IMG="${TMP_DIR}/${SOURCE}"

    echo >&2 "Downloading cloud image to: ${TMP_CLOUD_IMG}"
    wget -O "${TMP_CLOUD_IMG}" "${URL}"

    echo "${TMP_CLOUD_IMG}"
}

import-base-volume() {
    if [[ "${FETCH}" == "true" ]] && base-volume-exists; then
        echo "Deleting existing base image '${SOURCE}'..."
        virsh vol-delete --pool "${VMPOOL}" --vol "${SOURCE}"
    fi

    if base-volume-exists; then
        echo "Base image '${SOURCE}' already exists. Skipping import."
        return
    fi

    local downloaded
    downloaded=$(fetch-base-file)
    if [[ -z "${downloaded}" ]]; then
        echo "No file downloaded. Skipping import."
        return
    fi

    echo "Creating volume '${SOURCE}' in pool '${VMPOOL}'..."
    virsh vol-create-as "${VMPOOL}" "${SOURCE}" 10G --format qcow2
    virsh vol-upload --pool "${VMPOOL}" --vol "${SOURCE}" "${downloaded}"

    rm -f "${downloaded}"
    if [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" ]]; then
        rmdir "${TMP_DIR}"
    fi
}

clone-base() {
    VMVOL="vm-${VMNAME}.qcow2"

    if virsh vol-info --pool "${VMPOOL}" --vol "${VMVOL}" >/dev/null 2>&1; then
        if [[ "${RECREATE}" == "true" ]]; then
            delete-volume-if-exists "${VMVOL}"
        else
            echo "Volume '${VMVOL}' already exists. Aborting."
            exit 1
        fi
    fi

    virsh vol-clone --pool "${VMPOOL}" --vol "${SOURCE}" --newname "${VMVOL}"
}

resize-clone() {
    if [[ -n "${SIZE:-}" && "${SIZE}" =~ ^[0-9]+$ && "${SIZE}" -gt 0 ]]; then
        echo "Resizing volume '${VMVOL}' in pool '${VMPOOL}' to ${SIZE}G..."
        virsh vol-resize --pool "${VMPOOL}" --vol "${VMVOL}" "${SIZE}G"
    fi
}

create-extra-volume() {
    if [[ -z "${EXTRA_SIZE:-}" ]]; then
        return
    fi

    if [[ ! "${EXTRA_SIZE}" =~ ^[0-9]+$ || "${EXTRA_SIZE}" -le 0 ]]; then
        echo "Error: Additional disk size must be a positive integer number of GB."
        exit 1
    fi

    EXTRAVOL="vm-${VMNAME}-data.qcow2"

    if virsh vol-info --pool "${VMPOOL}" --vol "${EXTRAVOL}" >/dev/null 2>&1; then
        if [[ "${RECREATE}" == "true" ]]; then
            delete-volume-if-exists "${EXTRAVOL}"
        else
            echo "Volume '${EXTRAVOL}' already exists. Aborting."
            exit 1
        fi
    fi

    echo "Creating additional volume '${EXTRAVOL}' in pool '${VMPOOL}' (${EXTRA_SIZE}G)..."
    virsh vol-create-as "${VMPOOL}" "${EXTRAVOL}" "${EXTRA_SIZE}G" --format qcow2
}

vm-setup() {
    NET_ARG=""
    CLOUD_CONFIG_FILE="${CLOUD_CONFIG:-${LVTEMPLATES}/cloud-config.yml}"
    NET_CONFIG_FILE="${NET_CONFIG:-${LVTEMPLATES}/network-config.yml}"
    if [[ -f "${NET_CONFIG_FILE}" ]]; then
        NET_ARG=",network-config=${NET_CONFIG_FILE}"
    fi

    if [[ ! -f "${CLOUD_CONFIG_FILE}" ]]; then
        echo "Error: Cloud-init config file '${CLOUD_CONFIG_FILE}' not found."
        exit 1
    fi

    META_DATA_FILE="$(mktemp -t meta-data-XXXXXX)"
    trap 'rm -f "${META_DATA_FILE}"' EXIT
    cat > "${META_DATA_FILE}" <<EOF
instance-id: iid-${VMNAME}
local-hostname: ${VMNAME}
EOF

    local console_arg=()
    if [[ -n "${CONSOLE:-}" ]]; then
        console_arg=(--console "${CONSOLE}")
    fi

    local extra_disk_arg=()
    if [[ -n "${EXTRAVOL:-}" ]]; then
        extra_disk_arg=(--disk "vol=${VMPOOL}/${EXTRAVOL},bus=virtio,format=qcow2")
    fi

    local secondary_network_arg=()
    if [[ -n "${SECONDARY_NETWORK:-}" ]]; then
        secondary_network_arg=(--network "network=${SECONDARY_NETWORK},model=virtio")
    fi

    local virt_install_bin
    virt_install_bin="$(command -v virt-install)"
    if [[ -z "${virt_install_bin}" ]]; then
        echo "Error: virt-install not found in PATH."
        exit 1
    fi

    "${PYTHON:-/usr/bin/python3}" "${virt_install_bin}" \
        --name "${VMNAME}" \
        --memory "${VMEM}" \
        --vcpus "${VCPUS}" \
        --cpu host-model \
        --disk "vol=${VMPOOL}/${VMVOL},bus=virtio,format=qcow2" \
        "${extra_disk_arg[@]}" \
        --os-variant "${OSVARIANT}" \
        --network "network=${NETWORK},model=virtio" \
        "${secondary_network_arg[@]}" \
        --virt-type kvm \
        --import \
        --cloud-init "user-data=${CLOUD_CONFIG_FILE},meta-data=${META_DATA_FILE}" \
        --noautoconsole \
        "${console_arg[@]}" \
        --graphics=spice,port=-1,listen=localhost  \
        --qemu-commandline="-smbios type=1,serial=ds=nocloud;h=${VMNAME}.${DOMAIN}"
}

get-vminfo() {
    IP=${IP:-}
    if [ -f "${NET_CONFIG_FILE}" ] && [ -z "${IP}" ] ; then
        echo "Detected NET_CONFIG_FILE in use, aborting VM IP loop."
        exit 0
    fi
    timeout=60  # seconds
    if [[ ! -n "$IP" ]]; then
        echo "Waiting for $VMNAME IP address..."
        for ((i = 0; i < timeout; i++)); do
            DOM=$(virsh -q domifaddr "$VMNAME")
            read -ra arr <<<"$DOM"
            if [[ -n "${arr[@]}" ]]; then
                IP="${arr[3]%/*}"
            fi

            if [[ -n "$IP" ]]; then
                break
            fi
            sleep 1
        done
    fi

    if [[ -n "$IP" ]]; then
        echo ""
        echo "SSH to ${VMNAME}:"
        echo "  ssh ${IP}"
        echo "  ssh ubuntu@${IP}"
        echo ""
        echo "Checking for ${IP} in known_hosts file"
        grep -q ${IP} ${HOME}/.ssh/known_hosts &&
            echo "Found entry for ${IP}. Removing" &&
            (sed --in-place "/^${IP}/d" ~/.ssh/known_hosts) ||
            echo "No entries found for ${IP}"
    else
        echo "Timed out waiting for DHCP lease"
    fi
}

# -------------------------------------------------------------------------
# Main Execution Flow
# -------------------------------------------------------------------------
verify-commands
verify-pool
verify-vm-not-exist

import-base-volume
clone-base
resize-clone
create-extra-volume
vm-setup
get-vminfo
