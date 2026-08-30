#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=build/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_root
require_command git
require_command wget
require_command tar
require_command md5sum
ensure_dirs

ensure_builder_users() {
    if ! id builder >/dev/null 2>&1; then
        groupadd --gid 1000 builder 2>/dev/null || true
        useradd --uid 1000 --gid builder --create-home --shell /bin/bash builder
    fi

    # The cache is a bind mount from the host. jhalfs runs as builder and
    # needs to create its checkout directly below /work.
    install -d -m 1777 "$PROMPTTTY_WORK_DIR"
    chmod 1777 "$PROMPTTTY_WORK_DIR"
    install -d -m 0755 "$PROMPTTTY_LFS_DIR"
    install -d -m 1777 "$PROMPTTTY_SOURCE_DIR"
    chown builder:builder "$PROMPTTTY_SOURCE_DIR"

    # jhalfs creates and removes its temporary host-side lfs account as part
    # of the LFS book. Keep the build root writable by the orchestration user
    # before that setup step, without pre-creating lfs and tripping jhalfs's
    # safety check.
    if [[ ! -e "$PROMPTTTY_LFS_DIR/usr" ]]; then
        chown builder:builder "$PROMPTTTY_LFS_DIR"
    fi
}

ensure_book() {
    local book_dir="$PROMPTTTY_WORK_DIR/book"
    local book_tmp="$PROMPTTTY_WORK_DIR/.lfs-book-checkout"
    local actual_commit

    if [[ -f "$book_dir/general.ent" && -f "$book_dir/index.xml" ]]; then
        configure_release_book "$book_dir"
        return 0
    fi

    # The stable download archive is rendered HTML. jhalfs needs the XML
    # working copy instead, so use the official release tag from the LFS git
    # repository and verify the resolved commit before handing it to jhalfs.
    rm -rf "$book_tmp" "$book_dir"
    log "cloning the LFS ${PROMPTTTY_LFS_VERSION}-systemd XML book"
    git clone --depth=1 --branch "$PROMPTTTY_LFS_BOOK_REF" \
        "$PROMPTTTY_LFS_BOOK_REPO" "$book_tmp"
    actual_commit="$(git -C "$book_tmp" rev-parse HEAD)"
    [[ "$actual_commit" == "$PROMPTTTY_LFS_BOOK_COMMIT" ]] || die \
        "LFS book ref $PROMPTTTY_LFS_BOOK_REF resolved to $actual_commit, expected $PROMPTTTY_LFS_BOOK_COMMIT"
    [[ -f "$book_tmp/general.ent" && -f "$book_tmp/index.xml" ]] || die \
        'the checked-out LFS book does not contain the XML sources jhalfs needs'

    configure_release_book "$book_tmp"
    chown -R builder:builder "$book_tmp"
    mv "$book_tmp" "$book_dir"
}

configure_release_book() {
    local book_dir="$1"

    # The upstream git tag contains the source tree in its development
    # profile; the published 13.0 book switches these entities for release.
    # Keep that release profile so jhalfs resolves patches under /13.0 rather
    # than the development directory.
    sed -i \
        -e 's/<!ENTITY % development "INCLUDE">/<!ENTITY % development "IGNORE">/' \
        -e 's/<!ENTITY % release     "IGNORE">/<!ENTITY % release     "INCLUDE">/' \
        -e "s/<!ENTITY % relnum \"[^\"]*\">/<!ENTITY % relnum \"${PROMPTTTY_LFS_VERSION}\">/" \
        "$book_dir/general.ent"
    grep -q '<!ENTITY % release     "INCLUDE">' "$book_dir/general.ent" || \
        die 'failed to configure the LFS book for the stable release profile'
}

fetch_metadata() {
    fetch_url "$PROMPTTTY_LFS_BASE_URL/wget-list" "$PROMPTTTY_SOURCE_DIR/wget-list"
    fetch_url "$PROMPTTTY_LFS_BASE_URL/md5sums" "$PROMPTTTY_SOURCE_DIR/md5sums"
}

fetch_all_sources() {
    local url
    local filename

    fetch_metadata
    while IFS= read -r url; do
        [[ -z "$url" ]] && continue
        [[ "$url" == \#* ]] && continue
        filename="${url##*/}"
        fetch_url "$url" "$PROMPTTTY_SOURCE_DIR/$filename"
    done < "$PROMPTTTY_SOURCE_DIR/wget-list"

    log 'verifying the LFS source set'
    (cd "$PROMPTTTY_SOURCE_DIR" && md5sum --check md5sums)
}

prepare() {
    log 'preparing the LFS host workspace'
    ensure_builder_users
    ensure_book
    fetch_metadata
    mark_stage 00-toolchain
}

case "${1:-prepare}" in
    prepare)
        prepare
        ;;
    sources)
        prepare
        fetch_all_sources
        mark_stage 00-sources
        ;;
    *)
        die "usage: $0 [prepare|sources]"
        ;;
esac
