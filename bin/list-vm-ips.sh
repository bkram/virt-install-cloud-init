#!/bin/bash
# List libvirt VMs and their IP addresses on the primary network.

set -euo pipefail

SCRIPTHOME="$(dirname "$(dirname "$(realpath "$0")")")"
LVTEMPLATES="${SCRIPTHOME}/templates"

load_defaults() {
    if [[ -n "${LAUNCH_VM_INI:-}" && -e "${LAUNCH_VM_INI}" ]]; then
        # shellcheck source=/dev/null
        source "${LAUNCH_VM_INI}"
    elif [[ -e "${LVTEMPLATES}/launch-vm.ini" ]]; then
        # shellcheck source=/dev/null
        source "${LVTEMPLATES}/launch-vm.ini"
    else
        NETWORK=default
        DOMAIN=lan
    fi

    NETWORK="${NETWORK:-default}"
    DOMAIN="${DOMAIN:-lan}"
}

verify_commands() {
    local cmd
    for cmd in virsh awk paste; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            echo "Missing command '${cmd}'."
            exit 1
        fi
    done
}

get_primary_mac() {
    local vm_name="$1"

    virsh domiflist "${vm_name}" 2>/dev/null | awk -v net="${NETWORK}" '$3 == net { print $5; exit }'
}

get_ip_addrs() {
    local vm_name="$1"
    local primary_mac
    local lease_lines=""
    local hostname="${vm_name}"

    primary_mac="$(get_primary_mac "${vm_name}")"
    if [[ -n "${primary_mac}" ]]; then
        lease_lines="$(
            virsh net-dhcp-leases "${NETWORK}" 2>/dev/null | awk -v mac="${primary_mac}" '
                $0 ~ /^ / && $3 == mac { print $5 }
            '
        )"
    fi

    if [[ -z "${lease_lines}" ]]; then
        lease_lines="$(
            virsh net-dhcp-leases "${NETWORK}" 2>/dev/null | awk -v host="${hostname}" '
                $0 ~ /^ / && $6 == host { print $5 }
            '
        )"
    fi

    if [[ -n "${lease_lines}" ]]; then
        echo "${lease_lines}" | paste -sd "," -
    fi
}

main() {
    local vm_name
    local state
    local hostname
    local ip_addrs

    load_defaults
    verify_commands

    printf "%-20s %-10s %-26s %s\n" "VM" "State" "Hostname" "IP Addresses"
    printf "%-20s %-10s %-26s %s\n" "--------------------" "----------" "--------------------------" "------------------------------"

    while IFS= read -r vm_name; do
        [[ -n "${vm_name}" ]] || continue

        state="$(virsh domstate "${vm_name}" 2>/dev/null | tr -d '\r')"
        if [[ "${state}" == "shut off" ]]; then
            continue
        fi
        hostname="${vm_name}.${DOMAIN}"
        ip_addrs="$(get_ip_addrs "${vm_name}" || true)"

        printf "%-20s %-10s %-26s %s\n" "${vm_name}" "${state:-unknown}" "${hostname}" "${ip_addrs:-pending}"
    done < <(virsh list --all --name)
}

main "$@"
