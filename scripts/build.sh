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

fdisk_inst() {
    echo "g"    # Create a new empty GPT partition table
    echo "n"    # Add a new partition
    echo "1"    # Partition number
    echo ""     # First sector
    echo ""     # Last sector
    echo "t"    # Change a partition's type
    echo "uefi" # EFI System
    echo "w"    # Write changes
}

create_image() {
    local image="$1"
    if [ -z "$image" ]; then
        error "Please specify the image file."
        return 1
    fi
    dd if=/dev/zero of="$image" bs=1M count=64
    fdisk_inst | fdisk "$image"
    mkfs.fat -F32 -n "UEFI" "${image}"
}

sync_image() {
    local image="$1" manifest="$2" mnt

    mnt="$(mktemp -d)"
    defer "rm -rf $mnt"

    sudo mount "$image" "$mnt"
    defer "sudo umount $mnt"

    local from to
    while read -r from to; do
        if [ -z "$from" ] || [ "${from:0:1}" == "#" ]; then
            continue
        fi

        [ -z "$to" ] && to="$from"
        sudo mkdir -p "$mnt/$(dirname "$to")"
        sudo cp -vf "$from" "$mnt/$to"
    done < "$manifest"
}

if [ $# -lt 2 ]; then
    error "Please specify the image and manifest file."
    exit 1
fi

IMAGE="$1"
MANIFEST="$2"

create_image "$IMAGE" || exit 1
sync_image "$IMAGE" "$MANIFEST"
