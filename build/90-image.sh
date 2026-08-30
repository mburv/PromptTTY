#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=build/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_root
require_command cpio
require_command gzip
require_command grub-mkrescue
require_command md5sum

[[ -d "$PROMPTTTY_LFS_DIR/usr" ]] || die 'LFS target is missing; run the lfs stage first'
[[ -x "$PROMPTTTY_LFS_DIR/usr/bin/tar" || -x "$PROMPTTTY_LFS_DIR/bin/tar" ]] || die 'target tar is missing; cannot build the kernel in the LFS chroot'

KERNEL_VERSION="6.18.10"
KERNEL_ARCHIVE="linux-${KERNEL_VERSION}.tar.xz"
KERNEL_URL="https://www.kernel.org/pub/linux/kernel/v6.x/${KERNEL_ARCHIVE}"
KERNEL_MD5="660e706a43f634b1fcd911f8839d2f61"
fetch_url "$KERNEL_URL" "$PROMPTTTY_SOURCE_DIR/$KERNEL_ARCHIVE"
printf '%s  %s\n' "$KERNEL_MD5" "$PROMPTTTY_SOURCE_DIR/$KERNEL_ARCHIVE" | md5sum --check -

KERNEL_ROOT="$PROMPTTTY_LFS_DIR/usr/src/prompttty-kernel"
install -d -m 0755 "$KERNEL_ROOT"
install -m 0644 "$PROMPTTTY_SOURCE_DIR/$KERNEL_ARCHIVE" "$KERNEL_ROOT/$KERNEL_ARCHIVE"
install -m 0644 "$PROMPTTTY_REPO_DIR/configs/kernel.config" "$KERNEL_ROOT/kernel.config"
chown -R root:root "$KERNEL_ROOT"

KERNEL_SOURCE="$KERNEL_ROOT/linux-${KERNEL_VERSION}"
KERNEL_CONFIG_STAMP="$KERNEL_ROOT/.prompttty-kernel-config.sha256"
KERNEL_CONFIG_DIGEST="$(sha256sum "$PROMPTTTY_REPO_DIR/configs/kernel.config" | awk '{ print $1 }')"

if [[ ! -f "$KERNEL_SOURCE/arch/x86/boot/bzImage" ||
      ! -f "$KERNEL_CONFIG_STAMP" ||
      "$(<"$KERNEL_CONFIG_STAMP")" != "$KERNEL_CONFIG_DIGEST" ]]; then
    log "building Linux ${KERNEL_VERSION} in the LFS chroot"
    run_chroot "
        set -Eeuo pipefail
        cd /usr/src/prompttty-kernel
        if [[ ! -d linux-${KERNEL_VERSION} ]]; then
            tar -xf ${KERNEL_ARCHIVE}
        fi
        cd linux-${KERNEL_VERSION}
        cp ../kernel.config .config
        make olddefconfig
        make bzImage
    "
    printf '%s\n' "$KERNEL_CONFIG_DIGEST" > "$KERNEL_CONFIG_STAMP"
fi

ISO_ROOT="$PROMPTTTY_OUTPUT_DIR/iso-root"
rm -rf "$ISO_ROOT"
install -d -m 0755 "$ISO_ROOT/boot/grub"
install -m 0644 "$KERNEL_SOURCE/arch/x86/boot/bzImage" "$ISO_ROOT/boot/vmlinuz"

log 'packing the LFS target as an initramfs'
# Keep the full LFS target in the Docker volume for resumable builds, but ship
# only the runtime subset in the boot image. The compiler, headers, language
# development trees, documentation, and static archives are not needed by the
# current image or its shell launcher.
(cd "$PROMPTTTY_LFS_DIR" && \
    find . -xdev \
        \( \
            -path './jhalfs' -o \
            -path './sources' -o \
            -path './var/cache' -o \
            -path './usr/src/prompttty-kernel' -o \
            -path './usr/src/prompttty-node' -o \
            -path './usr/include' -o \
            -path './usr/libexec/gcc' -o \
            -path './usr/lib/gcc' -o \
            -path './usr/lib/python3.14' -o \
            -path './usr/lib/perl5' -o \
            -path './usr/lib/tcl8' -o \
            -path './usr/lib/tcl8.6' -o \
            -path './usr/lib/itcl4.3.4' -o \
            -path './usr/lib/gprofng' -o \
            -path './usr/share/doc' -o \
            -path './usr/share/man' -o \
            -path './usr/share/info' -o \
            -path './usr/share/locale' -o \
            -path './usr/share/i18n' -o \
            -path './usr/share/vim' -o \
            -path './usr/share/texi2any' -o \
            -path './usr/lib/grub' \
        \) -prune -o \
        \( \
            -type f \( -name '*.a' -o -name '*.la' -o -name '*.pyc' \) -o \
            -path './usr/bin/addr2line' -o \
            -path './usr/bin/ar' -o \
            -path './usr/bin/as' -o \
            -path './usr/bin/c++' -o \
            -path './usr/bin/c++filt' -o \
            -path './usr/bin/cc' -o \
            -path './usr/bin/cpp' -o \
            -path './usr/bin/elfedit' -o \
            -path './usr/bin/g++' -o \
            -path './usr/bin/gcc' -o \
            -path './usr/bin/gcov*' -o \
            -path './usr/bin/ld' -o \
            -path './usr/bin/ld.*' -o \
            -path './usr/bin/lto-*' -o \
            -path './usr/bin/make' -o \
            -path './usr/bin/ninja' -o \
            -path './usr/bin/nm' -o \
            -path './usr/bin/objcopy' -o \
            -path './usr/bin/objdump' -o \
            -path './usr/bin/ranlib' -o \
            -path './usr/bin/readelf' -o \
            -path './usr/bin/strip' -o \
            -path './usr/bin/x86_64-pc-linux-gnu-*' -o \
            -path './usr/bin/python*' -o \
            -path './usr/bin/perl*' -o \
            -path './usr/bin/tclsh*' -o \
            -path './usr/bin/wish*' \
        \) -prune -o \
        -print0 | cpio --null --create --format=newc --owner=0:0 | gzip --no-name --best > "$ISO_ROOT/boot/prompttty.initramfs.gz")

sed -e "s/@VERSION@/$PROMPTTTY_VERSION/g" \
    "$PROMPTTTY_REPO_DIR/build/grub.cfg" > "$ISO_ROOT/boot/grub/grub.cfg"

mkdir -p "$PROMPTTTY_OUTPUT_DIR/boot"
install -m 0644 "$ISO_ROOT/boot/vmlinuz" "$PROMPTTTY_OUTPUT_DIR/boot/vmlinuz"
install -m 0644 "$ISO_ROOT/boot/prompttty.initramfs.gz" "$PROMPTTTY_OUTPUT_DIR/boot/prompttty.initramfs.gz"

ISO_PATH="$PROMPTTTY_OUTPUT_DIR/PromptTTY-${PROMPTTTY_VERSION}.iso"
grub-mkrescue --output="$ISO_PATH" "$ISO_ROOT"

{
    printf 'PromptTTY version: %s\n' "$PROMPTTTY_VERSION"
    printf 'LFS book: %s-systemd\n' "$PROMPTTTY_LFS_VERSION"
    printf 'Kernel: %s\n' "$KERNEL_VERSION"
    printf 'Node.js enabled: %s\n' "$PROMPTTTY_WITH_NODE"
    sha256sum "$ISO_PATH" "$PROMPTTTY_OUTPUT_DIR/boot/vmlinuz" "$PROMPTTTY_OUTPUT_DIR/boot/prompttty.initramfs.gz"
} > "$PROMPTTTY_OUTPUT_DIR/manifest.txt"

log "image ready: $ISO_PATH"
