#!/bin/bash
# Show how libvirt can discover networking for one or more VMs.

set -euo pipefail

SCRIPTHOME="$(dirname "$(dirname "$(realpath "$0")")")"
LVTEMPLATES="${SCRIPTHOME}/templates"

usage() {
    echo "Usage: $(basename "$0") <vm-name> [vm-name ...]"
    exit 1
}

load_defaults() {
    if [[ -n "${LAUNCH_VM_INI:-}" && -e "${LAUNCH_VM_INI}" ]]; then
        # shellcheck source=/dev/null
        source "${LAUNCH_VM_INI}"
    elif [[ -e "${LVTEMPLATES}/launch-vm.ini" ]]; then
        # shellcheck source=/dev/null
        source "${LVTEMPLATES}/launch-vm.ini"
    else
        NETWORK=default
    fi

    NETWORK="${NETWORK:-default}"
}

show_vm() {
    local vm_name="$1"
    local guest_agent_state="unknown"

    echo "VM: ${vm_name}"

    if ! virsh dominfo "${vm_name}" >/dev/null 2>&1; then
        echo "  Status: not defined"
        echo
        return
    fi

    echo "  State: $(virsh domstate "${vm_name}" 2>/dev/null | tr -d '\r')"

    guest_agent_state="$(virsh qemu-agent-command "${vm_name}" '{"execute":"guest-ping"}' 2>/dev/null >/dev/null && echo connected || echo unavailable)"
    echo "  Guest agent: ${guest_agent_state}"

    echo "  Interfaces:"
    virsh domiflist "${vm_name}" 2>/dev/null | sed 's/^/    /'

    echo "  domifaddr:"
    if ! virsh domifaddr "${vm_name}" 2>/dev/null | sed 's/^/    /'; then
        echo "    unavailable"
    fi

    echo "  DHCP leases on ${NETWORK}:"
    local macs
    macs="$(virsh domiflist "${vm_name}" 2>/dev/null | awk 'NR > 2 && $5 ~ /^([0-9a-f]{2}:){5}[0-9a-f]{2}$/ {print $5}')"
    if [[ -z "${macs}" ]] || ! virsh net-dhcp-leases "${NETWORK}" 2>/dev/null | awk -v macs="${macs}" '
        BEGIN { split(macs, a, /[ \n]+/); found = 0 }
        NR == 1 || NR == 2 { next }
        {
            for (i in a) {
                if (a[i] != "" && $3 == a[i]) { print "    " $0; found = 1 }
            }
        }
        END {
            if (found == 0) {
                print "    none"
            }
        }
    '; then
        echo "    unavailable"
    fi

    echo
}

main() {
    local vm_name

    if (( $# == 0 )); then
        usage
    fi

    load_defaults

    for vm_name in "$@"; do
        show_vm "${vm_name}"
    done
}

main "$@"
