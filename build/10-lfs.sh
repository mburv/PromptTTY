#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=build/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_root
require_command git
require_command runuser
require_command sed
require_command grep
require_command chown
require_command script
ensure_dirs

"$SCRIPT_DIR/00-toolchain.sh" prepare

JHALFS_DIR="${PROMPTTTY_JHALFS_DIR:-${PROMPTTTY_WORK_DIR}/jhalfs}"
JHALFS_BUILD_DIR="${PROMPTTTY_LFS_DIR}/jhalfs"
BOOK_DIR="${PROMPTTTY_BOOK_DIR:-${PROMPTTTY_WORK_DIR}/book}"
CONFIGURATION="$JHALFS_DIR/configuration"

clone_jhalfs() {
    install -d -m 1777 "$(dirname "$JHALFS_DIR")"

    if [[ ! -d "$JHALFS_DIR/.git" ]]; then
        log 'cloning official jhalfs'
        rm -rf "$JHALFS_DIR"
        runuser -u builder -- git clone "$PROMPTTTY_JHALFS_REPO" "$JHALFS_DIR"
    fi

    if [[ -n "$PROMPTTTY_JHALFS_REF" ]]; then
        runuser -u builder -- git -C "$JHALFS_DIR" fetch --tags --prune origin
        runuser -u builder -- git -C "$JHALFS_DIR" checkout --force "$PROMPTTTY_JHALFS_REF"
    fi

    chown -R builder:builder "$JHALFS_DIR"
}

write_configuration() {
    local template="$SCRIPT_DIR/jhalfs.configuration"

    cp "$template" "$CONFIGURATION"
    sed -i \
        -e "s|__BOOK_DIR__|$BOOK_DIR|g" \
        -e "s|__LFS_DIR__|$PROMPTTTY_LFS_DIR|g" \
        -e "s|__SOURCE_DIR__|$PROMPTTTY_SOURCE_DIR|g" \
        -e "s|__JOBS__|$PROMPTTTY_JOBS|g" \
        "$CONFIGURATION"

    if [[ "${PROMPTTTY_OFFLINE:-0}" == 1 ]]; then
        sed -i 's/^GETPKG=y/GETPKG=n/' "$CONFIGURATION"
    fi

    chown builder:builder "$CONFIGURATION"
}

patch_linux_headers_command() {
    local command_file="$JHALFS_BUILD_DIR/lfs-commands/chapter05/503-linux-headers"

    [[ -f "$command_file" ]] || die 'jhalfs did not generate the Linux headers command'

    if ! runuser -u builder -- grep -q '^LOCAL_SRC_DIR=' "$command_file"; then
        log 'routing Linux header extraction through the container-local filesystem'
        runuser -u builder -- sed -i \
            -e '/^SRC_DIR=${ROOT}sources$/a\LOCAL_SRC_DIR=${TMPDIR:-/tmp}/prompttty-linux-headers' \
            -e '/^SRC_DIR=${ROOT}sources$/a\rm -rf "$LOCAL_SRC_DIR"' \
            -e '/^SRC_DIR=${ROOT}sources$/a\mkdir -p "$LOCAL_SRC_DIR"' \
            -e 's|^tar -xf \$PACKAGE$|tar -xf "$SRC_DIR/$PACKAGE" -C "$LOCAL_SRC_DIR"|' \
            -e 's|^cd \$PKGDIR$|cd "$LOCAL_SRC_DIR/$PKGDIR"|' \
            -e '/^rm -rf \$PKGDIR$/c\rm -rf "$LOCAL_SRC_DIR" "$PKGDIR"' \
            "$command_file"
    fi

    if ! runuser -u builder -- grep -q '^rm -rf "\$LFS/usr/include"$' "$command_file"; then
        log 'making Linux header installation resumable after a partial copy'
        runuser -u builder -- sed -i \
            -e '/^cp -rv usr\/include \$LFS\/usr$/i\rm -rf "$LFS/usr/include"' \
            "$command_file"
    fi
}

reset_jhalfs_setup_stamps() {
    if id lfs >/dev/null 2>&1; then
        return 0
    fi

    log 'resetting jhalfs setup stamps after an interrupted host-side build'
    if [[ -L "$PROMPTTTY_LFS_DIR/bin" && -L "$PROMPTTTY_LFS_DIR/lib" && -L "$PROMPTTTY_LFS_DIR/sbin" ]]; then
        touch "$JHALFS_BUILD_DIR/401-creatingminlayout"
    else
        rm -f "$JHALFS_BUILD_DIR/401-creatingminlayout"
    fi
    rm -f \
        "$JHALFS_BUILD_DIR/402-addinguser" \
        "$JHALFS_BUILD_DIR/403-settingenvironment" \
        "$JHALFS_BUILD_DIR/mk_SETUP" \
        "$JHALFS_BUILD_DIR/mk_LUSER" \
        "$JHALFS_BUILD_DIR/mk_SUDO" \
        "$JHALFS_BUILD_DIR/mk_CHROOT" \
        "$JHALFS_BUILD_DIR/mk_BOOT" \
        "$JHALFS_BUILD_DIR/create-sbu_du-report"
}

initialize_jhalfs_setup() {
    if id lfs >/dev/null 2>&1; then
        return 0
    fi

    reset_jhalfs_setup_stamps
    log 'recreating the jhalfs setup and environment before resuming the toolchain'
    runuser -u builder -- env \
        JHALFS_DIR="$JHALFS_DIR" \
        JHALFS_BUILD_DIR="$JHALFS_BUILD_DIR" \
        bash -c '
        set -Eeuo pipefail
        cd "$JHALFS_DIR"
        script --quiet --return --command "stty rows 24 cols 80; make -C \"$JHALFS_BUILD_DIR\" mk_SETUP" /dev/null
    '

    # Seeded bootstrap tools contain nested directories that the original
    # bind-mounted build created as builder. LFS package steps run as lfs and
    # must be able to extend those directories during a resumed build.
    chown -R lfs:lfs "$PROMPTTTY_LFS_DIR/tools"

    runuser -u lfs -- env HOME=/home/lfs \
        make -C "$JHALFS_BUILD_DIR" 403-settingenvironment

    # Keep the setup targets older than any completed LFS toolchain target.
    # This lets make recreate the temporary lfs account without rebuilding
    # successful package steps whose outputs are still present.
    touch -d 2000-01-01T00:00:00Z \
        "$JHALFS_BUILD_DIR/401-creatingminlayout" \
        "$JHALFS_BUILD_DIR/402-addinguser" \
        "$JHALFS_BUILD_DIR/403-settingenvironment"
}

run_jhalfs() {
    log 'running the LFS 13.0-systemd book through jhalfs'
    export JHALFS_DIR JHALFS_BUILD_DIR

    runuser -u builder -- env \
        JHALFS_DIR="$JHALFS_DIR" \
        JHALFS_BUILD_DIR="$JHALFS_BUILD_DIR" \
        bash -c '
        set -Eeuo pipefail
        cd "$JHALFS_DIR"
        # jhalfs asks for confirmation before it loads a saved configuration.
        # Keep that prompt deterministic while leaving the build resumable.
        touch configuration.old
        touch -d 2000-01-01T00:00:00Z configuration.old
        printf "yes\n" | ./jhalfs run
    '

    patch_linux_headers_command
    initialize_jhalfs_setup

    # util-linux script creates the pty, but Docker does not give the
    # non-interactive parent a useful window size. Set one before make so
    # jhalfs terminal-size safety check can run in CI and containers.
    runuser -u builder -- env \
        JHALFS_DIR="$JHALFS_DIR" \
        JHALFS_BUILD_DIR="$JHALFS_BUILD_DIR" \
        bash -c '
        set -Eeuo pipefail
        cd "$JHALFS_DIR"
        script --quiet --return --command "stty rows 24 cols 80; make -C \"$JHALFS_BUILD_DIR\"" /dev/null
    '
}

if stage_done 10-lfs && [[ -x "$PROMPTTTY_LFS_DIR/bin/bash" ]] && [[ -x "$PROMPTTTY_LFS_DIR/usr/lib/systemd/systemd" || -x "$PROMPTTTY_LFS_DIR/lib/systemd/systemd" ]]; then
    log 'LFS base stage already completed; keeping the resumable target'
    exit 0
fi

clone_jhalfs
write_configuration
run_jhalfs

[[ -x "$PROMPTTTY_LFS_DIR/bin/bash" ]] || die 'jhalfs finished without /bin/bash in the target'
[[ -x "$PROMPTTTY_LFS_DIR/usr/lib/systemd/systemd" || -x "$PROMPTTTY_LFS_DIR/lib/systemd/systemd" ]] || die 'jhalfs finished without systemd in the target'

log 'LFS base system is ready'
mark_stage 10-lfs
