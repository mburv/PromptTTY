#!/usr/bin/env bash

set -Eeuo pipefail

PROMPTTTY_REPO_DIR="${PROMPTTTY_REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
PROMPTTTY_WORK_DIR="${PROMPTTTY_WORK_DIR:-/work}"
PROMPTTTY_LFS_DIR="${PROMPTTTY_LFS_DIR:-${PROMPTTTY_WORK_DIR}/lfs}"
PROMPTTTY_SOURCE_DIR="${PROMPTTTY_SOURCE_DIR:-${PROMPTTTY_WORK_DIR}/sources}"
PROMPTTTY_OUTPUT_DIR="${PROMPTTTY_OUTPUT_DIR:-${PROMPTTTY_REPO_DIR}/out}"
PROMPTTTY_STATE_DIR="${PROMPTTTY_STATE_DIR:-${PROMPTTTY_WORK_DIR}/state}"
PROMPTTTY_JOBS="${PROMPTTTY_JOBS:-$(nproc 2>/dev/null || printf '2')}"
PROMPTTTY_WITH_NODE="${PROMPTTTY_WITH_NODE:-0}"
PROMPTTTY_PI_VERSION="${PROMPTTTY_PI_VERSION:-0.84.4}"
PROMPTTTY_FORCE_OVERLAY="${PROMPTTTY_FORCE_OVERLAY:-0}"
PROMPTTTY_VERSION="${PROMPTTTY_VERSION:-0.1}"
PROMPTTTY_LFS_VERSION="${PROMPTTTY_LFS_VERSION:-13.0}"
PROMPTTTY_LFS_BOOK_REPO="${PROMPTTTY_LFS_BOOK_REPO:-https://git.linuxfromscratch.org/lfs.git}"
PROMPTTTY_LFS_BOOK_REF="${PROMPTTTY_LFS_BOOK_REF:-r13.0}"
PROMPTTTY_LFS_BOOK_COMMIT="${PROMPTTTY_LFS_BOOK_COMMIT:-de54c2453179f2743912edafacfe2d309919efae}"
PROMPTTTY_LFS_BASE_URL="${PROMPTTTY_LFS_BASE_URL:-https://www.linuxfromscratch.org/lfs/downloads/stable-systemd}"
PROMPTTTY_JHALFS_REPO="${PROMPTTTY_JHALFS_REPO:-https://git.linuxfromscratch.org/jhalfs.git}"
PROMPTTTY_JHALFS_REF="${PROMPTTTY_JHALFS_REF:-${JHALFS_REF:-a76d857fd82454bd3677a7a210b1a996b272d7e0}}"

LFS="$PROMPTTTY_LFS_DIR"
export LFS

log() {
    printf '\n==> %s\n' "$*"
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

require_root() {
    [[ "$(id -u)" -eq 0 ]] || die 'build stages must run as root inside the Linux builder container'
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "required command is missing: $1"
}

ensure_dirs() {
    install -d -m 0755 "$PROMPTTTY_WORK_DIR" "$PROMPTTTY_SOURCE_DIR" "$PROMPTTTY_STATE_DIR" "$PROMPTTTY_OUTPUT_DIR"
}

fetch_url() {
    local url="$1"
    local destination="$2"
    local partial="${destination}.part"

    if [[ -s "$destination" ]]; then
        return 0
    fi

    log "downloading $(basename "$destination")"
    wget --https-only --tries=5 --timeout=60 --continue --output-document="$partial" "$url"
    mv -f "$partial" "$destination"
}

stage_marker() {
    printf '%s/%s.done' "$PROMPTTTY_STATE_DIR" "$1"
}

stage_done() {
    [[ -f "$(stage_marker "$1")" ]]
}

mark_stage() {
    install -d -m 0755 "$PROMPTTTY_STATE_DIR"
    printf '%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$(stage_marker "$1")"
}

run_chroot() {
    local command_string="$1"
    local chroot_term="${TERM:-linux}"

    chroot "$PROMPTTTY_LFS_DIR" /usr/bin/env -i \
        HOME=/root \
        TERM="$chroot_term" \
        LANG=C.UTF-8 \
        LC_ALL=C \
        PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        MAKEFLAGS="-j${PROMPTTTY_JOBS}" \
        /bin/bash -lc "$command_string"
}

target_unit_dir() {
    if [[ -d "$PROMPTTTY_LFS_DIR/usr/lib/systemd/system" ]]; then
        printf '/usr/lib/systemd/system\n'
    elif [[ -d "$PROMPTTTY_LFS_DIR/lib/systemd/system" ]]; then
        printf '/lib/systemd/system\n'
    else
        die 'the LFS systemd unit directory was not found'
    fi
}

target_systemd_path() {
    local candidate

    for candidate in /usr/lib/systemd/systemd /lib/systemd/systemd; do
        if [[ -x "$PROMPTTTY_LFS_DIR$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    die 'the LFS systemd executable was not found'
}
