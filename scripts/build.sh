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

if [ $# -lt 2 ]; then
    error "Please specify the image file and UEFI application."
    exit 1
fi

IMAGE="$1"
UEFI="$2"

create_image "$IMAGE"
LOOP_DEV="$(sudo losetup --show -fP "$IMAGE")"
MOUNT_DIR="$(mktemp -d)"

sudo mount "${LOOP_DEV}" "$MOUNT_DIR"
if [ -n "$3" ]; then
    sudo mkdir -p "$MOUNT_DIR$(dirname "$3")"
fi
sudo cp "$UEFI" "$MOUNT_DIR$3"
