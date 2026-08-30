#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=build/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_root
[[ -d "$PROMPTTTY_LFS_DIR/usr" ]] || die 'LFS target is missing; run the lfs stage first'

PI_PACKAGE='@earendil-works/pi-coding-agent'
PI_VERSION="$PROMPTTTY_PI_VERSION"

if stage_done 40-agents &&
    [[ "$PROMPTTTY_FORCE_OVERLAY" != 1 ]] &&
    { [[ -x "$PROMPTTTY_LFS_DIR/usr/bin/pi" ]] || [[ -x "$PROMPTTTY_LFS_DIR/usr/local/bin/pi" ]]; }; then
    log 'agent registry already applied'
    exit 0
fi

[[ "$PROMPTTTY_WITH_NODE" == 1 ]] || die 'Pi is bundled by default; build with WITH_NODE=1 to install its Node.js runtime'

if [[ -x "$PROMPTTTY_LFS_DIR/usr/bin/npm" ]]; then
    NPM_PATH=/usr/bin/npm
elif [[ -x "$PROMPTTTY_LFS_DIR/usr/local/bin/npm" ]]; then
    NPM_PATH=/usr/local/bin/npm
else
    die 'target npm is missing; the Node.js layer must finish before installing Pi'
fi

install -d -m 0755 "$PROMPTTTY_LFS_DIR/etc/prompttty/agents.d"
for example in "$PROMPTTTY_REPO_DIR"/agents/*.conf; do
    [[ -f "$example" ]] || continue
    install -m 0644 "$example" "$PROMPTTTY_LFS_DIR/etc/prompttty/agents.d/$(basename "$example")"
done

# The runtime resolver is a systemd-resolved stub symlink, but no systemd
# instance is running while packages are installed in the chroot. Temporarily
# copy the builder's resolver configuration so npm can reach its registry, then
# restore the runtime symlink even if the install fails.
RESOLV_CONF="$PROMPTTTY_LFS_DIR/etc/resolv.conf"
RESOLV_TARGET=''
if [[ -L "$RESOLV_CONF" ]]; then
    RESOLV_TARGET="$(readlink "$RESOLV_CONF")"
    rm -f "$RESOLV_CONF"
    install -m 0644 /etc/resolv.conf "$RESOLV_CONF"
fi

restore_resolver() {
    if [[ -n "$RESOLV_TARGET" ]]; then
        rm -f "$RESOLV_CONF"
        ln -s "$RESOLV_TARGET" "$RESOLV_CONF"
    fi
}

trap restore_resolver EXIT

log "installing Pi coding agent ${PI_VERSION}"
run_chroot "
    set -Eeuo pipefail
    export npm_config_cache=/tmp/prompttty-npm-cache
    ${NPM_PATH} install --global --ignore-scripts --no-audit --no-fund ${PI_PACKAGE}@${PI_VERSION}
    command -v pi >/dev/null 2>&1
    pi --version
    rm -rf /tmp/prompttty-npm-cache /root/.npm
"

restore_resolver
trap - EXIT
mark_stage 40-agents
