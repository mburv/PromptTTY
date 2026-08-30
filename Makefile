SHELL := /bin/bash

PROJECT_ROOT := $(abspath .)
BUILDER_IMAGE ?= prompttty-lfs:13.0
BUILDER_PLATFORM ?= linux/amd64
JOBS ?= 4
# Pi is bundled in the default image and runs on the target Node.js runtime.
WITH_NODE ?= 1
PI_VERSION ?= 0.84.4
FORCE ?= 0
JHALFS_REF ?= a76d857fd82454bd3677a7a210b1a996b272d7e0
WORK_CACHE ?= $(PROJECT_ROOT)/.cache
WORK_VOLUME ?= prompttty-lfs-cache-13.0

DOCKER_RUN = docker run --rm --privileged --platform $(BUILDER_PLATFORM) \
	--env PROMPTTTY_JOBS=$(JOBS) \
	--env PROMPTTTY_WITH_NODE=$(WITH_NODE) \
	--env PROMPTTTY_PI_VERSION=$(PI_VERSION) \
	--env PROMPTTTY_FORCE_OVERLAY=$(FORCE) \
	--env PROMPTTTY_JHALFS_REF=$(JHALFS_REF) \
	--volume "$(PROJECT_ROOT):/src" \
	--volume "$(WORK_VOLUME):/work" \
	--volume "$(WORK_CACHE):/seed:ro" \
	$(BUILDER_IMAGE)

.PHONY: check builder sources lfs overlay kernel image qemu qemu-iso clean

check:
	bash build/check.sh

builder:
	mkdir -p "$(WORK_CACHE)"
	docker volume create "$(WORK_VOLUME)" >/dev/null
	docker build --platform $(BUILDER_PLATFORM) --tag $(BUILDER_IMAGE) --file build/Containerfile .

sources: builder
	mkdir -p "$(WORK_CACHE)"
	$(DOCKER_RUN) sources

lfs: builder
	mkdir -p "$(WORK_CACHE)"
	$(DOCKER_RUN) lfs

overlay: builder
	mkdir -p "$(WORK_CACHE)"
	$(DOCKER_RUN) overlay

kernel: builder
	mkdir -p "$(WORK_CACHE)"
	$(DOCKER_RUN) kernel

image: builder
	mkdir -p "$(WORK_CACHE)"
	$(DOCKER_RUN) image

qemu:
	bash build/run-qemu.sh kernel

qemu-iso:
	bash build/run-qemu.sh iso

clean:
	rm -rf "$(PROJECT_ROOT)/out" "$(WORK_CACHE)"
	docker volume rm "$(WORK_VOLUME)" >/dev/null 2>&1 || true
