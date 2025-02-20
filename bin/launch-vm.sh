#!/bin/bash
# (c) 2020 Mark de Bruijn <mrdebruijn@gmail.com>
# Deploy a cloud image to local libvirt instance using ONE pool: VMPOOL

VER="1.8.0 (20250219)"

set -euo pipefail

# shellcheck disable=SC2046
SCRIPTHOME="$(dirname "$(dirname "$(realpath "$0")")")"

# -------------------------------------------------------------------------
# Load config from .ini or fall back to defaults
# -------------------------------------------------------------------------
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
    VMPOOL=vm-pool
    # If desired, set CONSOLE="pty,target_type=virtio" or similar
fi

function usage() {
    echo "Usage: $(basename "$0") [options]"
    echo "Deploy a cloud image to local libvirt using a single pool (VMPOOL)."
    echo
    echo "Options:"
    echo "  -d DISTRIB   Distribution name (e.g. 'ubuntu22.04' for .ini lookup)"
    echo "  -n NAME      VM Name"
    echo "  -c VCPUS     Number of CPUs (default: ${VCPUS})"
    echo "  -m MEM       Memory in MB (default: ${VMEM})"
    echo "  -s SIZE      Resize the cloned disk to SIZE GB (optional)"
    echo "  -f           Force a fresh download if the base volume already exists"
    echo "  -v           Show version and exit"
    echo
    echo "Expects a .ini in \${LVTEMPLATES} named <DISTRIB>.ini defining:"
    echo "  SOURCE    (e.g. 'source-ubuntu22.04.img')"
    echo "  URL       (cloud image download URL)"
    echo "  OSVARIANT (e.g. 'ubuntu22.04' or 'debian10')"
    echo "  VMPOOL    (storage pool, default: vm-pool)"
    echo
    exit 1
}

# -------------------------------------------------------------------------
# Parse arguments
# -------------------------------------------------------------------------
optstring="d:n:c:m:s:fvh"

FETCH=""   # We only set this if -f is passed

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
        f)
            FETCH='true'
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

# If no VM name or distribution provided, exit
if [[ -z "${VMNAME:-}" || -z "${DISTRIBUTION:-}" ]]; then
    usage
fi

# -------------------------------------------------------------------------
# Load distribution-specific .ini (where SOURCE, URL, OSVARIANT come from)
# -------------------------------------------------------------------------
if [ -e "${LVTEMPLATES}/${DISTRIBUTION}.ini" ]; then
    # shellcheck source=/dev/null
    source "${LVTEMPLATES}/${DISTRIBUTION}.ini"
else
    echo "Distribution template '${DISTRIBUTION}.ini' not found in ${LVTEMPLATES}"
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
        echo "Example commands:"
        echo "  virsh pool-define-as ${VMPOOL} dir - - - - /var/lib/libvirt/images/vms"
        echo "  virsh pool-build ${VMPOOL}"
        echo "  virsh pool-start ${VMPOOL}"
        echo "  virsh pool-autostart ${VMPOOL}"
        exit 1
    fi
}

verify-vm-not-exist() {
    if virsh dominfo --domain "${VMNAME}" >/dev/null 2>&1; then
        echo "Error: The VM '${VMNAME}' already exists."
        exit 1
    fi
}

base-volume-exists() {
    virsh vol-info --pool "${VMPOOL}" --vol "${SOURCE}" >/dev/null 2>&1
}

# Global definitions for the download
TMP_DIR=""
TMP_CLOUD_IMG=""

# -------------------------------------------------------------------------
# Always downloads a fresh cloud image to a temporary directory if called.
# -------------------------------------------------------------------------
fetch-base-file() {
    TMP_DIR="$(mktemp -d -t cloudimg-XXXXXX)"
    TMP_CLOUD_IMG="${TMP_DIR}/${SOURCE}"

    echo >&2 "Downloading cloud image to: ${TMP_CLOUD_IMG}"
    wget -O "${TMP_CLOUD_IMG}" "${URL}"

    # Output just the path
    echo "${TMP_CLOUD_IMG}"
}

# -------------------------------------------------------------------------
# Create/upload the base image if it's missing, or if -f is passed remove old first
# -------------------------------------------------------------------------
import-base-volume() {
    # 1) If the user wants to force a fresh download and the volume exists, remove it
    if [[ "${FETCH}" == "true" ]] && base-volume-exists; then
        echo "Base image '${SOURCE}' exists and '-f' was given. Deleting old volume..."
        virsh vol-delete --pool "${VMPOOL}" --vol "${SOURCE}"
    fi

    # 2) If after that step it still exists, skip import
    if base-volume-exists; then
        echo "Base image '${SOURCE}' already exists in pool '${VMPOOL}'. No need to import."
        return
    fi

    # 3) The volume doesn't exist, so let's download and import
    local downloaded
    downloaded=$(fetch-base-file)
    if [[ -z "${downloaded}" ]]; then
        echo "No file downloaded. Skipping import."
        return
    fi

    echo "Creating volume '${SOURCE}' in pool '${VMPOOL}'..."
    virsh vol-create-as "${VMPOOL}" "${SOURCE}" 10G --format qcow2

    echo "Uploading cloud image to pool '${VMPOOL}'..."
    virsh vol-upload --pool "${VMPOOL}" --vol "${SOURCE}" "${downloaded}"

    echo "Cleaning up temporary files..."
    rm -f "${downloaded}"
    if [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" ]]; then
        rmdir "${TMP_DIR}"
    fi
}

# -------------------------------------------------------------------------
# Clone the base volume for this VM
# -------------------------------------------------------------------------
clone-base() {
    VMVOL="vm-${VMNAME}.qcow2"

    echo "Cloning base volume '${SOURCE}' to '${VMVOL}' in pool '${VMPOOL}'..."

    if virsh vol-info --pool "${VMPOOL}" --vol "${VMVOL}" >/dev/null 2>&1; then
        echo "Volume '${VMVOL}' already exists in '${VMPOOL}'. Aborting."
        exit 1
    fi

    virsh vol-clone --pool "${VMPOOL}" --vol "${SOURCE}" --newname "${VMVOL}"
}

# -------------------------------------------------------------------------
# Resize the cloned volume if requested
# -------------------------------------------------------------------------
resize-clone() {
    if [[ -n "${SIZE:-}" && "${SIZE}" =~ ^[0-9]+$ && "${SIZE}" -gt 0 ]]; then
        echo "Resizing volume '${VMVOL}' in pool '${VMPOOL}' to ${SIZE}G..."
        virsh vol-resize --pool "${VMPOOL}" --vol "${VMVOL}" "${SIZE}G"
    fi
}

# -------------------------------------------------------------------------
# Install/launch the VM
# -------------------------------------------------------------------------
vm-setup() {
    echo "Launching VM '${VMNAME}' with volume '${VMVOL}' in pool '${VMPOOL}'..."

    virt-install \
        --name "${VMNAME}" \
        --memory "${VMEM}" \
        --vcpus "${VCPUS}" \
        --disk "vol=${VMPOOL}/${VMVOL},bus=virtio,format=qcow2" \
        --os-variant "${OSVARIANT}" \
        --network "network=${NETWORK},model=virtio" \
        --virt-type kvm \
        --import \
        --cloud-init "user-data=${LVTEMPLATES}/cloud-config.yml" \
        --wait \
        --noautoconsole \
        --console "${CONSOLE:-}" \
        --video none \
        --qemu-commandline="-smbios type=1,serial=ds=nocloud;h=${VMNAME}.${DOMAIN}"
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
vm-setup
