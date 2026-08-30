#!/usr/bin/env bash

set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$REPO_DIR"

for script in build/*.sh build/lib/*.sh; do
    bash -n "$script"
done

for script in rootfs/usr/local/bin/*; do
    bash -n "$script"
done

test -f build/Containerfile
test -f build/jhalfs.configuration
test -f configs/kernel.config
test -f systemd/prompttty.service
test -f systemd/prompttty-serial.service
test -f systemd/prompttty.target
test -x rootfs/usr/local/bin/prompttty
test -x rootfs/usr/local/bin/prompttty-agent
test -x rootfs/usr/local/bin/prompttty-shell

grep -q 'BOOK_LFS_SYSD=y' build/jhalfs.configuration
grep -q 'WORKING_COPY=y' build/jhalfs.configuration
grep -q '^WITH_NODE ?= 1$' Makefile
grep -q '^PI_VERSION ?= ' Makefile
grep -q 'CONFIG_VIRTIO_NET=y' configs/kernel.config
grep -q '^CONFIG_PACKET=y$' configs/kernel.config
grep -q 'CONFIG_USB_EHCI_HCD=y' configs/kernel.config
grep -q 'CONFIG_USB_UHCI_HCD=y' configs/kernel.config
grep -q 'CONFIG_USB_XHCI_HCD=y' configs/kernel.config
grep -q 'CONFIG_USB_HID=y' configs/kernel.config
grep -q 'CONFIG_HID_GENERIC=y' configs/kernel.config
grep -q 'CONFIG_INPUT_KEYBOARD=y' configs/kernel.config
grep -q 'CONFIG_BLK_DEV_INITRD=y' configs/kernel.config
grep -q '^CONFIG_AUTOFS_FS=y$' configs/kernel.config
grep -q '^CONFIG_BINFMT_MISC=y$' configs/kernel.config
grep -q 'prompttty.console=serial' build/grub.cfg
grep -q '^RUNMAKE=n$' build/jhalfs.configuration
grep -q 'JHALFS_REF ?= a76d857fd82454bd3677a7a210b1a996b272d7e0' Makefile
grep -q '^Requires=basic.target$' systemd/prompttty.target
grep -q '^After=basic.target systemd-networkd.service systemd-resolved.service$' systemd/prompttty.target
grep -q '^PROMPTTTY_AGENT=pi$' rootfs/etc/prompttty/prompttty.conf
grep -q '^PROMPTTTY_AGENT_COMMAND=pi$' agents/pi.conf
grep -q 'linux-x64.tar.xz' build/30-node.sh
grep -q 'sha256sum --check' build/30-node.sh
grep -q "@earendil-works/pi-coding-agent" build/40-agents.sh

git diff --check

printf 'PromptTTY checks passed.\n'
