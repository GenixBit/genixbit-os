# Makefile — GenixBit OS build orchestrator
SHELL         := /usr/bin/env bash
.DEFAULT_GOAL := current

DEPS := \
  binutils \
  curl \
  debootstrap \
  dosfstools \
  dpkg \
  gnupg \
  grub-efi-amd64 \
  grub-pc-bin \
  grub2-common \
  mtools \
  python3 \
  squashfs-tools \
  xorriso

.PHONY: current packages vm clean bootstrap menuconfig buildtorrent help

help:
	@echo "Usage:"
	@echo "  make          (or make current)   Build the current GenixBit OS ISO"
	@echo "  make packages                     Build native GenixBit .deb packages"
	@echo "  make vm                           Boot the newest dist/ ISO in QEMU"
	@echo "  make menuconfig                   Configure build options (TUI)"
	@echo "  make clean                        Remove generated build artifacts"
	@echo "  make bootstrap                    Validate environment and dependencies"
	@echo "  make buildtorrent                 Generate torrents for dist/*.iso"

bootstrap:
	@if [ ! -r /etc/os-release ]; then \
	  echo "Error: /etc/os-release is unavailable. ISO builds require a Linux build host."; \
	  exit 1; \
	fi
	@host="$$(. /etc/os-release; printf '%s' "$${VERSION_CODENAME:-}")"; \
	target="$$(sed -n 's/^export TARGET_UBUNTU_VERSION="\([^"]*\)"/\1/p' args.sh | head -n 1)"; \
	if [ -z "$$target" ]; then \
	  echo "Error: TARGET_UBUNTU_VERSION is not defined in args.sh"; \
	  exit 1; \
	fi; \
	if [ "$$host" != "$$target" ]; then \
	  echo "Error: Host codename '$$host' != target '$$target'"; \
	  echo "Build the ISO on the matching Ubuntu release. You can still boot an existing ISO with 'make vm'."; \
	  exit 1; \
	fi
	@sudo -v
	@missing="" ; \
	for pkg in $(DEPS); do \
	  if ! dpkg -s $$pkg >/dev/null 2>&1; then \
	    missing="$$missing $$pkg"; \
	  fi; \
	done; \
	if [ -n "$$missing" ]; then \
	  echo "Missing packages:$$missing"; \
	  echo "Installing missing dependencies..."; \
	  sudo apt-get update && sudo apt-get install -y $$missing; \
	else \
	  echo "[MAKE] All required packages are already installed."; \
	fi

menuconfig:
	@./menuconfig.sh

packages: bootstrap
	@echo "[MAKE] Building native GenixBit OS packages..."
	@python3 ./tools/build-all-debs.py

current: packages
	@echo "[MAKE] Building GenixBit OS ISO..."
	@./build.sh

vm:
	@bash ./tools/local/run-vm.sh

buildtorrent:
	@if [ ! -d dist ]; then \
	  echo "[ERROR] dist/ directory not found. Run 'make' first."; \
	  exit 1; \
	fi; \
	shopt -s nullglob; isos=(dist/*.iso); \
	if [ $${#isos[@]} -eq 0 ]; then \
	  echo "[ERROR] No ISO files found in dist/."; \
	  exit 1; \
	fi; \
	if ! command -v mktorrent &>/dev/null; then \
	  echo "[MAKE] Installing mktorrent..."; \
	  sudo apt-get update && sudo apt-get install -y mktorrent; \
	fi; \
	tracker=$$(mktemp); \
	curl -fsSL -o "$$tracker" https://raw.githubusercontent.com/ngosang/trackerslist/master/trackers_best.txt; \
	mapfile -t raw < "$$tracker"; \
	rm "$$tracker"; \
	announce_args=(); \
	for t in "$${raw[@]}"; do \
	  [ -n "$$t" ] && announce_args+=(-a "$$t"); \
	done; \
	for iso in "$${isos[@]}"; do \
	  base="$${iso%.iso}"; \
	  echo "[MAKE] Generating torrent for $$(basename "$$iso")..."; \
	  rm -f "$${base}.torrent"; \
	  mktorrent "$${announce_args[@]}" -o "$${base}.torrent" "$$iso"; \
	done; \
	echo "[MAKE] Torrent generation complete."

clean:
	@echo "[MAKE] Cleaning generated build artifacts..."
	@./clean_all.sh
	@rm -rf ./build ./dist
	@find ./packages/build-debs -mindepth 1 ! -name .gitkeep -delete 2>/dev/null || true
	@echo "[MAKE] Clean complete. Local VM disks under .local-artifacts/ are preserved."
