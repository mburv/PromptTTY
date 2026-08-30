# PromptTTY

PromptTTY is a small, agent-oriented Linux image built from source with
Linux From Scratch (LFS). The first milestone is a BIOS-bootable ISO that
starts systemd, brings up DHCP networking, and enters the PromptTTY agent
console instead of presenting a normal shell.

The build is pinned to the stable [LFS 13.0-systemd book](https://www.linuxfromscratch.org/lfs/downloads/stable-systemd/LFS-BOOK-13.0-NOCHUNKS.html)
and installs the official Linux x64 Node.js runtime for the Pi layer. LFS is
built from its book instructions by
the official [jhalfs](https://www.linuxfromscratch.org/alfs/) automation; the
PromptTTY files are applied only after the base LFS system is complete.

## Build

The supported host path is Docker Desktop on macOS or Linux. The builder is
forced to `linux/amd64`, which matches the initial QEMU kernel configuration
and also works on Apple Silicon through Docker's emulation layer.

```sh
make check
make builder
make image
```

The first build is intentionally a full LFS source build and can take hours.
It needs a large Docker volume; allow roughly 16 GB of free space for sources
and build products. On macOS, the LFS tree
lives in the case-sensitive named Docker volume
`prompttty-lfs-cache-13.0`; the host `.cache/` directory is only a download
and bootstrap seed cache. This avoids filename collisions in Linux headers on
the default case-insensitive macOS filesystem. The resulting files are written
to `out/`:

```text
out/PromptTTY-0.1.iso
out/boot/vmlinuz
out/boot/prompttty.initramfs.gz
```

Node.js is enabled by default because the image bundles the Pi coding-agent
CLI (`@earendil-works/pi-coding-agent`), pinned to the version in `Makefile`.
Pi still needs credentials at runtime; use its
`/login` flow or provide the relevant provider environment variable.

```sh
make image
```

`WITH_NODE=0` is not valid for the default image because it removes Pi's
runtime. Set `PI_VERSION=x.y.z` when intentionally selecting another pinned Pi
release.

Useful incremental targets are:

```sh
make sources                 # download and verify the LFS source set
make lfs                     # build only the LFS base system
make overlay                 # apply networking, agents, and PromptTTY
make kernel                  # build the LFS kernel and ISO artifacts
make overlay FORCE=1         # reapply edited overlay files without rebuilding LFS
make kernel                  # rebuild/repack the ISO after the overlay change
make clean                   # remove generated output, seed cache, and Docker volume
```

`make image` runs the stages in order. A failed package can be resumed by
rerunning the same command while the named Docker volume is retained. The
overlay stages normally skip once their state markers exist. When files under
`rootfs/`, `systemd/`, `agents/`, or the networking policy change, use
`make overlay FORCE=1` and then `make kernel`; this preserves the completed LFS
base and only reapplies the customized layer before rebuilding the image.
The repository pins jhalfs to a reviewed commit; set `JHALFS_REF=trunk` or another
reviewed ref when intentionally changing that automation revision.

## Run

Install QEMU separately on the host, then use the direct-kernel headless mode
to see the PromptTTY console over the serial terminal:

```sh
make qemu
```

This uses QEMU user networking (`10.0.2.0/24`), so systemd-networkd should
obtain an address automatically. To boot the actual ISO through GRUB instead
of loading the kernel and initramfs directly:

```sh
make qemu-iso
```

The ISO has two GRUB entries: the normal `tty1` console and a serial-console
variant. On real hardware, the normal entry is the default. The headless
target selects the serial variant so it is usable without a display.

## Runtime model

The image keeps systemd as PID 1. `prompttty.service` owns tty1, while tty2
remains the recovery login. The normal console is the configured agent
backend, not a Bash prompt. The built-in `prompttty` command can:

```text
agent [name]    run a configured agent backend
doctor          inspect system, network, and backend availability
network         show network state
shell           explicitly open a Bash recovery shell
version         show PromptTTY release information
```

The kernel builds automount support in (`CONFIG_AUTOFS_FS=y`) because the
image boots without a separate kernel-modules tree. This keeps systemd's
automount units, including its `binfmt_misc` setup, available from the first
PID 1 startup.

Pi, Codex, Claude Code, OpenCode, and custom backends are discovered by
command name. Pi is included and is the default backend. The other provider
CLIs and all credentials remain outside the image; install a provider CLI in
the target system or set the executable in `/etc/prompttty/agents.d/*.conf`
before making another backend the default.

The image is intentionally image-based: rebuild the complete filesystem and
ISO when the system changes. It does not pretend to be a package-managed
distribution yet.

## Repository layout

```text
build/                  containerized LFS and image stages
configs/                QEMU-oriented Linux kernel configuration
rootfs/                 PromptTTY configuration and launcher files
systemd/                PromptTTY units and target
agents/                 backend configuration examples
```

The LFS base is deliberately kept separate from the PromptTTY overlay so the
base can be rebuilt or audited against the book without mixing local policy
into upstream package instructions.
