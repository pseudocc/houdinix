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
    ovmf_fd="$(dpkg-query -L ovmf | grep -E "OVMF_?$fd_type.fd$" | head -n1)"
    if [ -z "$ovmf_fd" ]; then
        error "Could not find the firmware image for '$fd_type'."
        return 1
    fi
    echo "$ovmf_fd"
}

usage() {
    echo "Usage: $0 <command> <image>"
    echo "command: 'shell' or 'boot'"
    exit 1
}

if [ $# -ne 2 ]; then
    error "Please specify the command and the image file."
    usage
fi

uefi_shell() {
    local code_fd vars_fd tmp_vars_fd

    code_fd="$(ovmf_fd CODE_4M)"
    vars_fd="$(ovmf_fd VARS_4M)"

    tmp_vars_fd="$(mktemp)"
    cp "$vars_fd" "$tmp_vars_fd"

    debug "tmp_vars_fd: '$vars_fd' -> '$tmp_vars_fd'"
    defer "rm -f $tmp_vars_fd"

    qemu-system-x86_64 -cpu qemu64 \
        -drive if=pflash,format=raw,unit=0,file="$code_fd",readonly=on \
        -drive if=pflash,format=raw,unit=1,file="$tmp_vars_fd" \
        -drive file="$1",format=raw \
        -net none -nographic
}

boot_image() {
    qemu-system-x86_64 -cpu qemu64 \
        -bios "$(ovmf_fd)" \
        -drive file="$1",format=raw \
        -net none
}

case "$1" in
    shell)
        check_ovmf && uefi_shell "$2"
        ;;
    boot)
        check_ovmf && boot_image "$2"
        ;;
    *)
        error "Invalid command: $1"
        usage
        ;;
esac
