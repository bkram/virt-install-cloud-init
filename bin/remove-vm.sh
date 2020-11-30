#!/bin/bash
# (c) 2020 Mark de Bruijn <mrdebruijn@gmail.com>
# Remove libvirt Domain and all of its attachd storage
VER="1.0 (20201130)"

function usage() {
    echo "Usage: $(basename "$0") [-d domain]" 2>&1
    echo 'Removes Domain and all of its attached storage'
    echo '   -d     domain'
    echo '   -v     show version'
    exit 1
}

# Define list of arguments expected in the input
optstring="d:v"

while getopts ${optstring} arg; do
    case ${arg} in
    d)
        DOMAIN="${OPTARG}"
        ;;
    v)
        SVER='true'
        ;;
    ?)
        echo "Invalid option: -${OPTARG}."
        echo
        usage
        ;;
    esac
done

# If no input argument found, exit the script with usage
if [[ ${#} -eq 0 ]]; then
    usage
fi

# Show version if requested
if [[ ${SVER} == true ]]; then
    echo "${0} version: ${VER}"
    exit 0
fi

# Remove Domain if detected
if [ -n "${DOMAIN}" ]; then
    if virsh dominfo --domain "${DOMAIN}" >/dev/null 2>&1; then
        virsh destroy --domain "${DOMAIN}"
        virsh undefine --domain "${DOMAIN}" --remove-all-storage
    else
        echo "The Domain '${DOMAIN}' was not detected on this host"
    fi
fi
