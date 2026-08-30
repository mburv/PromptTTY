#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=build/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_root
[[ -d "$PROMPTTTY_LFS_DIR/usr" ]] || die 'LFS target is missing; run the lfs stage first'

if stage_done 50-prompttty && [[ "$PROMPTTTY_FORCE_OVERLAY" != 1 ]]; then
    log 'PromptTTY overlay already applied'
    exit 0
fi

log 'installing PromptTTY runtime and systemd policy'
cp -a "$PROMPTTTY_REPO_DIR/rootfs/." "$PROMPTTTY_LFS_DIR/"
install -d -m 0755 "$PROMPTTTY_LFS_DIR/etc/systemd/system"
for unit in "$PROMPTTTY_REPO_DIR"/systemd/*.service "$PROMPTTTY_REPO_DIR"/systemd/*.target; do
    [[ -f "$unit" ]] || continue
    install -m 0644 "$unit" "$PROMPTTTY_LFS_DIR/etc/systemd/system/$(basename "$unit")"
done

if ! grep -q '^prompt:' "$PROMPTTTY_LFS_DIR/etc/group"; then
    run_chroot 'groupadd prompt'
fi
if ! grep -q '^prompt:' "$PROMPTTTY_LFS_DIR/etc/passwd"; then
    run_chroot 'useradd --no-user-group --gid prompt --create-home --home-dir /home/prompt --shell /usr/local/bin/prompttty-shell prompt'
fi

# The account must be created in the target's passwd/group databases, not in
# the temporary Docker host that is running this stage.
PROMPT_UID="$(awk -F: '$1 == "prompt" { print $3 }' "$PROMPTTTY_LFS_DIR/etc/passwd")"
PROMPT_GID="$(awk -F: '$1 == "prompt" { print $3 }' "$PROMPTTTY_LFS_DIR/etc/group")"
[[ -n "$PROMPT_UID" && -n "$PROMPT_GID" ]] || die 'could not resolve the PromptTTY target account'
# The initramfs packer normalizes ownership to root:root for reproducibility.
# Keep the workspace traversable and writable after that normalization so the
# prompt user can start the service and let an agent write session files.
install -d -m 1777 -o "$PROMPT_UID" -g "$PROMPT_GID" "$PROMPTTTY_LFS_DIR/home/prompt/workspace"

# Pi stores its session state below $HOME/.pi rather than in the configured
# workspace. The initramfs packer also normalizes this directory's ownership,
# so pre-create it with a sticky writable mode for the prompt user.
install -d -m 1777 -o "$PROMPT_UID" -g "$PROMPT_GID" "$PROMPTTTY_LFS_DIR/home/prompt/.pi"

touch "$PROMPTTTY_LFS_DIR/etc/shells"
if ! grep -q '^/usr/local/bin/prompttty-shell$' "$PROMPTTTY_LFS_DIR/etc/shells" 2>/dev/null; then
    printf '%s\n' /usr/local/bin/prompttty-shell >> "$PROMPTTTY_LFS_DIR/etc/shells"
fi

SYSTEMD_BIN="$(target_systemd_path)"
if [[ ! -e "$PROMPTTTY_LFS_DIR/init" && ! -L "$PROMPTTTY_LFS_DIR/init" ]]; then
    ln -s "$SYSTEMD_BIN" "$PROMPTTTY_LFS_DIR/init"
fi

UNIT_DIR="$(target_unit_dir)"
install -d -m 0755 \
    "$PROMPTTTY_LFS_DIR/etc/systemd/system/prompttty.target.wants" \
    "$PROMPTTTY_LFS_DIR/etc/systemd/system/getty.target.wants"

# PromptTTY replaces only tty1. tty2 keeps the ordinary LFS getty as the
# recovery path.
ln -sfn /dev/null "$PROMPTTTY_LFS_DIR/etc/systemd/system/getty@tty1.service"
ln -sfn "$UNIT_DIR/getty@.service" \
    "$PROMPTTTY_LFS_DIR/etc/systemd/system/getty.target.wants/getty@tty2.service"
ln -sfn /etc/systemd/system/prompttty.target "$PROMPTTTY_LFS_DIR/etc/systemd/system/default.target"
ln -sfn /etc/systemd/system/prompttty.service \
    "$PROMPTTTY_LFS_DIR/etc/systemd/system/prompttty.target.wants/prompttty.service"
ln -sfn /etc/systemd/system/prompttty-serial.service \
    "$PROMPTTTY_LFS_DIR/etc/systemd/system/prompttty.target.wants/prompttty-serial.service"

if [[ ! -e "$PROMPTTTY_LFS_DIR/etc/machine-id" && ! -L "$PROMPTTTY_LFS_DIR/etc/machine-id" ]]; then
    : > "$PROMPTTTY_LFS_DIR/etc/machine-id"
fi

mark_stage 50-prompttty
