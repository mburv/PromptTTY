#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=build/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_root
[[ -d "$PROMPTTTY_LFS_DIR/etc" ]] || die 'LFS target is missing; run the lfs stage first'

if stage_done 20-network && [[ "$PROMPTTTY_FORCE_OVERLAY" != 1 ]]; then
    log 'network overlay already applied'
    exit 0
fi

UNIT_DIR="$(target_unit_dir)"
install -d -m 0755 \
    "$PROMPTTTY_LFS_DIR/etc/systemd/network" \
    "$PROMPTTTY_LFS_DIR/etc/systemd/system/multi-user.target.wants" \
    "$PROMPTTTY_LFS_DIR/etc/prompttty"

# jhalfs can materialize the LFS book's illustrative static network file from
# the configuration values. Remove those generated examples so the runtime
# policy below is the only matching .network file and DHCP works on either
# classic eth0 or predictable en* interface names.
find "$PROMPTTTY_LFS_DIR/etc/systemd/network" -maxdepth 1 \
    \( -type f -o -type l \) -name '*.network' -delete

install -m 0644 "$PROMPTTTY_REPO_DIR/rootfs/etc/systemd/network/80-prompttty.network" \
    "$PROMPTTTY_LFS_DIR/etc/systemd/network/80-prompttty.network"
install -m 0644 "$PROMPTTTY_REPO_DIR/rootfs/etc/hostname" "$PROMPTTTY_LFS_DIR/etc/hostname"
install -m 0644 "$PROMPTTTY_REPO_DIR/rootfs/etc/hosts" "$PROMPTTTY_LFS_DIR/etc/hosts"

[[ -e "$PROMPTTTY_LFS_DIR$UNIT_DIR/systemd-networkd.service" ]] || die 'systemd-networkd.service is missing from the LFS target'
[[ -e "$PROMPTTTY_LFS_DIR$UNIT_DIR/systemd-networkd-wait-online.service" ]] || die 'systemd-networkd-wait-online.service is missing from the LFS target'
[[ -e "$PROMPTTTY_LFS_DIR$UNIT_DIR/systemd-resolved.service" ]] || die 'systemd-resolved.service is missing from the LFS target'

ln -sfn "$UNIT_DIR/systemd-networkd.service" \
    "$PROMPTTTY_LFS_DIR/etc/systemd/system/multi-user.target.wants/systemd-networkd.service"
ln -sfn "$UNIT_DIR/systemd-resolved.service" \
    "$PROMPTTTY_LFS_DIR/etc/systemd/system/multi-user.target.wants/systemd-resolved.service"
# DHCP continues in the background; the agent console must not block on it.
rm -f \
    "$PROMPTTTY_LFS_DIR/etc/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service"

if [[ -e "$PROMPTTTY_LFS_DIR/etc/resolv.conf" || -L "$PROMPTTTY_LFS_DIR/etc/resolv.conf" ]]; then
    rm -f "$PROMPTTTY_LFS_DIR/etc/resolv.conf"
fi
ln -s /run/systemd/resolve/stub-resolv.conf "$PROMPTTTY_LFS_DIR/etc/resolv.conf"

if [[ ! -e "$PROMPTTTY_LFS_DIR/etc/machine-id" && ! -L "$PROMPTTTY_LFS_DIR/etc/machine-id" ]]; then
    : > "$PROMPTTTY_LFS_DIR/etc/machine-id"
fi

mark_stage 20-network
