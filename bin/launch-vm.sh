#!/bin/bash
# (c) 2020 Mark de Bruijn <mrdebruijn@gmail.com>
# Deploy a cloud image to a libvirt-managed hypervisor

VER="1.9.0 (20250227)"

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
    echo "  -f           Force a fresh download if the base volume already exists"
    echo "  -v           Show version and exit"
    echo
    exit 1
}

# -------------------------------------------------------------------------
# Parse arguments
# -------------------------------------------------------------------------
optstring="d:n:c:m:s:fvh"

FETCH=""

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
        echo "Error: The VM '${VMNAME}' already exists."
        exit 1
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
        echo "Volume '${VMVOL}' already exists. Aborting."
        exit 1
    fi

    virsh vol-clone --pool "${VMPOOL}" --vol "${SOURCE}" --newname "${VMVOL}"
}

resize-clone() {
    if [[ -n "${SIZE:-}" && "${SIZE}" =~ ^[0-9]+$ && "${SIZE}" -gt 0 ]]; then
        echo "Resizing volume '${VMVOL}' in pool '${VMPOOL}' to ${SIZE}G..."
        virsh vol-resize --pool "${VMPOOL}" --vol "${VMVOL}" "${SIZE}G"
    fi
}

vm-setup() {
    CLOUD_CONFIG_FILE="${CLOUD_CONFIG:-${LVTEMPLATES}/cloud-config.yml}"

    if [[ ! -f "${CLOUD_CONFIG_FILE}" ]]; then
        echo "Error: Cloud-init config file '${CLOUD_CONFIG_FILE}' not found."
        exit 1
    fi

    virt-install \
        --name "${VMNAME}" \
        --memory "${VMEM}" \
        --vcpus "${VCPUS}" \
        --disk "vol=${VMPOOL}/${VMVOL},bus=virtio,format=qcow2" \
        --os-variant "${OSVARIANT}" \
        --network "network=${NETWORK},model=virtio" \
        --virt-type kvm \
        --import \
        --cloud-init "user-data=${CLOUD_CONFIG_FILE}" \
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
