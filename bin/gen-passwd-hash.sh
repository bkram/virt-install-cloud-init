#!/bin/bash
# Generate a SHA-512 password hash suitable for cloud-init "passwd"

set -euo pipefail

usage() {
    echo "Usage: $(basename "$0") [--stdin | --password <pw>]"
    echo
    echo "Generate a SHA-512 password hash for cloud-init."
    echo
    echo "Options:"
    echo "  --stdin           Read password from stdin (first line)"
    echo "  --password <pw>   Read password from argument (not recommended)"
    echo "  --raw             Output only the hash (no YAML)"
    echo "  -h, --help        Show this help"
    echo
    echo "Examples:"
    echo "  $(basename "$0")"
    echo "  echo 'secret' | $(basename "$0") --stdin --raw"
    echo
}

read_password_interactive() {
    local pass1 pass2 tty_in
    if [[ -r /dev/tty ]]; then
        tty_in="/dev/tty"
    else
        tty_in="/dev/stdin"
    fi
    read -r -s -p "Password: " pass1 <"${tty_in}" 1>&2
    printf '\n' >&2
    read -r -s -p "Confirm: " pass2 <"${tty_in}" 1>&2
    printf '\n' >&2
    if [[ "${pass1}" != "${pass2}" ]]; then
        echo "Error: passwords do not match." >&2
        exit 1
    fi
    printf '%s' "${pass1}"
}

read_password_stdin() {
    local pass
    IFS= read -r pass || true
    if [[ -z "${pass}" ]]; then
        echo "Error: empty password from stdin." >&2
        exit 1
    fi
    printf '%s' "${pass}"
}

password_source="interactive"
output_mode="yaml"
password_arg=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --stdin)
            password_source="stdin"
            shift
            ;;
        --password)
            password_source="arg"
            password_arg="${2:-}"
            shift 2
            ;;
        --raw)
            output_mode="raw"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Error: unknown option '$1'." >&2
            usage
            exit 1
            ;;
    esac
done

password=""
case "${password_source}" in
    stdin)
        password="$(read_password_stdin)"
        ;;
    arg)
        if [[ -z "${password_arg}" ]]; then
            echo "Error: --password requires a value." >&2
            exit 1
        fi
        password="${password_arg}"
        ;;
    *)
        password="$(read_password_interactive)"
        ;;
esac

hash=""
if command -v openssl >/dev/null 2>&1; then
    hash="$(printf '%s' "${password}" | openssl passwd -6 -stdin)"
elif command -v mkpasswd >/dev/null 2>&1; then
    hash="$(printf '%s' "${password}" | mkpasswd --method=sha-512 --stdin)"
else
    echo "Error: requires 'openssl' or 'mkpasswd' to be installed." >&2
    exit 1
fi

case "${output_mode}" in
    raw)
        printf '%s\n' "${hash}"
        ;;
    *)
        printf 'passwd: "%s"\n' "${hash}"
        ;;
esac
