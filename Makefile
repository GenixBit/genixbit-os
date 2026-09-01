SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

.PHONY: help current vm clean check

help:
	@printf '%s\n' \
	  'GenixBit OS local developer commands:' \
	  '  make current  Validate the supported Ubuntu host and build native packages + ISO.' \
	  '  make vm       Boot the newest dist/GenixBitOS-*.iso in the persistent local QEMU VM.' \
	  '  make clean    Remove generated build output; preserve .local-artifacts/ VM disks.' \
	  '  make check    Run local build/VM entry-point contract checks.'

current:
	@bash tools/local/build-current.sh

vm:
	@bash tools/local/run-vm.sh

clean:
	@bash tools/local/clean-build.sh

check:
	@bash tests/infrastructure/test-local-developer-entrypoints.sh
