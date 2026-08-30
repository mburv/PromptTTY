#!/usr/bin/env bash

set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${PROMPTTTY_OUTPUT_DIR:-$REPO_DIR/out}"
VERSION="${PROMPTTTY_VERSION:-0.1}"
QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"

command -v "$QEMU_BIN" >/dev/null 2>&1 || {
    printf 'error: %s is not installed or is not on PATH\n' "$QEMU_BIN" >&2
    exit 1
}

ISO_PATH="$OUTPUT_DIR/PromptTTY-${VERSION}.iso"
KERNEL_PATH="$OUTPUT_DIR/boot/vmlinuz"
INITRAMFS_PATH="$OUTPUT_DIR/boot/prompttty.initramfs.gz"

case "${1:-kernel}" in
    kernel)
        [[ -f "$KERNEL_PATH" && -f "$INITRAMFS_PATH" ]] || {
            printf 'error: build the image first (missing %s or %s)\n' "$KERNEL_PATH" "$INITRAMFS_PATH" >&2
            exit 1
        }
        exec "$QEMU_BIN" \
            -m "${PROMPTTTY_QEMU_MEMORY:-2048}" \
            -smp "${PROMPTTTY_QEMU_CPUS:-2}" \
            -display none \
            -serial mon:stdio \
            -kernel "$KERNEL_PATH" \
            -initrd "$INITRAMFS_PATH" \
            -append 'console=tty0 console=ttyS0,115200n8 loglevel=4 systemd.unit=prompttty.target prompttty.console=serial' \
            -netdev user,id=net0 \
            -device virtio-net-pci,netdev=net0 \
            -no-reboot
        ;;
    iso)
        [[ -f "$ISO_PATH" ]] || {
            printf 'error: build the image first (missing %s)\n' "$ISO_PATH" >&2
            exit 1
        }
        exec "$QEMU_BIN" \
            -m "${PROMPTTTY_QEMU_MEMORY:-2048}" \
            -smp "${PROMPTTTY_QEMU_CPUS:-2}" \
            -cdrom "$ISO_PATH" \
            -display curses \
            -serial mon:stdio \
            -netdev user,id=net0 \
            -device virtio-net-pci,netdev=net0 \
            -no-reboot
        ;;
    *)
        printf 'usage: %s [kernel|iso]\n' "$0" >&2
        exit 2
        ;;
esac
