#!/usr/bin/env bash

set -Eeuo pipefail

seed_work_volume() {
    local marker=/work/.prompttty-seed-v1

    [[ -f "$marker" ]] && return 0

    install -d -m 1777 /work /work/sources /work/lfs
    chmod 1777 /work

    # The host cache remains useful for downloads, but the LFS target and
    # build tree must live on Docker's case-sensitive Linux filesystem.
    if [[ -d /seed/sources ]]; then
        find /seed/sources -mindepth 1 -maxdepth 1 -type f \
            -exec cp -a {} /work/sources/ \;
    fi

    # Reuse completed bootstrap outputs when the seed cache came from an
    # earlier bind-mounted build. Do not copy the target root itself: it may
    # contain a partial case-colliding header tree from macOS.
    if [[ -d /seed/lfs/tools ]]; then
        install -d -m 0755 /work/lfs/tools
        cp -a /seed/lfs/tools/. /work/lfs/tools/
    fi
    if [[ -d /seed/lfs/jhalfs ]]; then
        install -d -m 1777 /work/lfs/jhalfs
        cp -a /seed/lfs/jhalfs/. /work/lfs/jhalfs/
    fi

    if [[ -e /work/lfs/tools ]]; then
        chown -R builder:builder /work/lfs/tools
    fi
    if [[ -e /work/lfs/jhalfs ]]; then
        chown -R builder:builder /work/lfs/jhalfs
    fi
    touch "$marker"
}

seed_work_volume

case "${1:-image}" in
    prepare)
        /src/build/00-toolchain.sh prepare
        ;;
    sources)
        /src/build/00-toolchain.sh sources
        ;;
    lfs)
        /src/build/00-toolchain.sh prepare
        /src/build/10-lfs.sh
        ;;
    overlay)
        /src/build/20-network.sh
        /src/build/30-node.sh
        /src/build/40-agents.sh
        /src/build/50-prompttty.sh
        ;;
    kernel)
        /src/build/90-image.sh
        ;;
    image)
        /src/build/00-toolchain.sh prepare
        /src/build/10-lfs.sh
        /src/build/20-network.sh
        /src/build/30-node.sh
        /src/build/40-agents.sh
        /src/build/50-prompttty.sh
        /src/build/90-image.sh
        ;;
    shell)
        exec /bin/bash
        ;;
    *)
        printf 'usage: %s {prepare|sources|lfs|overlay|kernel|image|shell}\n' "$0" >&2
        exit 2
        ;;
esac
