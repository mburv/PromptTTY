#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=build/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_root
require_command sha256sum

if [[ "$PROMPTTTY_WITH_NODE" != 1 ]]; then
    log 'Node.js layer disabled (PROMPTTTY_WITH_NODE=0)'
    exit 0
fi

[[ -d "$PROMPTTTY_LFS_DIR/usr" ]] || die 'LFS target is missing; run the lfs stage first'

if stage_done 30-node; then
    log 'Node.js layer already applied'
    exit 0
fi

NODE_VERSION="22.22.0"
NODE_ARCHIVE="node-v${NODE_VERSION}-linux-x64.tar.xz"
NODE_URL="https://nodejs.org/dist/v${NODE_VERSION}/${NODE_ARCHIVE}"
NODE_SHA256="9aa8e9d2298ab68c600bd6fb86a6c13bce11a4eca1ba9b39d79fa021755d7c37"

fetch_url "$NODE_URL" "$PROMPTTTY_SOURCE_DIR/$NODE_ARCHIVE"
printf '%s  %s\n' "$NODE_SHA256" "$PROMPTTTY_SOURCE_DIR/$NODE_ARCHIVE" | sha256sum --check -

NODE_ROOT="$PROMPTTTY_LFS_DIR/usr/src/prompttty-node"
rm -rf "$NODE_ROOT"
install -d -m 0755 "$NODE_ROOT"
install -m 0644 "$PROMPTTTY_SOURCE_DIR/$NODE_ARCHIVE" "$NODE_ROOT/$NODE_ARCHIVE"

log "installing the official Node.js ${NODE_VERSION} Linux x64 runtime"
run_chroot "
    set -Eeuo pipefail
    tar --no-same-owner --strip-components=1 -xJf /usr/src/prompttty-node/${NODE_ARCHIVE} -C /usr
    node --version
    npm --version
"

rm -rf "$NODE_ROOT"
mark_stage 30-node
