#!/bin/bash
# vim: ts=4:et

PROJECT_ROOT="$(git rev-parse --show-toplevel)"
. "$PROJECT_ROOT/deps/pseudosh/include.sh"

include "utils.sh"
include "defer.sh"

if [ "$0" != "${BASH_SOURCE[0]}" ]; then
    error "This script must be executed, not sourced."
    exit 1
fi

check_ovmf() {
    if dpkg --status ovmf | grep -q 'Status: install ok installed'; then
        return 0
    else
        error "Please install the 'ovmf' package."
        return 1
    fi
}

ovmf_fd() {
    local ovmf_fd fd_type="$1"
    if [ -z "$fd_type" ]; then
        error "Please specify the type of the firmware image."
        return 1
    fi

    ovmf_fd="$(dpkg-query -L ovmf | grep -E "OVMF_$fd_type.fd$")"
    if [ -z "$ovmf_fd" ]; then
        error "Could not find the firmware image for '$fd_type'."
        return 1
    fi
    echo "$ovmf_fd"
}

if [ -z "$1" ]; then
    error "Please specify the disk image."
    exit 1
fi

check_ovmf || exit 1
sudo qemu-system-x86_64 -cpu qemu64 \
    -drive if=pflash,format=raw,unit=0,file="$(ovmf_fd CODE_4M)" \
    -drive if=pflash,format=raw,unit=1,file="$(ovmf_fd VARS_4M)" \
    -net none -nographic "$1"
