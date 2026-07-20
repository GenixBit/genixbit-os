# Makefile —— GenixBit OS build orchestrator
SHELL         := /usr/bin/env bash
.DEFAULT_GOAL := current

DEPS := \
  binutils \
  curl \
  debootstrap \
  gnupg \
  squashfs-tools \
  xorriso \
  grub-pc-bin \
  grub-efi-amd64 \
  grub2-common \
  mtools \
  dosfstools

.PHONY: current clean bootstrap menuconfig buildtorrent help

help:
	@echo "Usage:"
	@echo "  make          (or make current)   Build current language"
	@echo "  make menuconfig                   Configure build options (TUI)"
	@echo "  make clean                        Remove build artifacts"
	@echo "  make bootstrap                    Validate environment and deps"
	@echo "  make buildtorrent                 Generate torrents for dist/*.iso"

bootstrap:
	@if [ "$$(id -u)" -eq 0 ]; then \
	  echo "Error: Do not run as root"; \
	  exit 1; \
	fi
	@if ! lsb_release -i | grep -qE "(Ubuntu|Debian|Tuxedo|Anduin|GenixBit)"; then \
	  echo "Error: Unsupported OS — only Ubuntu, Debian, Tuxedo, AnduinOS or GenixBit OS allowed"; \
	  exit 1; \
	fi
	@host=$$(lsb_release -cs); \
	target=$$(grep -oP 'export TARGET_UBUNTU_VERSION="\K[^"]+' args.sh); \
	if [ "$$host" != "$$target" ]; then \
	  echo "Error: Host codename '$$host' != target '$$target'"; \
	  echo "Build machine must run the same Ubuntu release as the target ISO."; \
	  exit 1; \
	fi
	@sudo -n true

	@missing="" ; \
	for pkg in $(DEPS); do \
	  if ! dpkg -s $$pkg >/dev/null 2>&1; then \
	    missing="$$missing $$pkg"; \
	  fi; \
	done; \
	if [ -n "$$missing" ]; then \
	  echo "Missing packages:$$missing"; \
	  echo "Installing missing dependencies..."; \
	  sudo -n apt-get update && sudo -n apt-get install -y $$missing; \
	else \
	  echo "[MAKE] All required packages are already installed."; \
	fi

menuconfig:
	@./menuconfig.sh

current: bootstrap
	@echo "[MAKE] Building current language..."
	@./build.sh

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
	@echo "[MAKE] Cleaning build artifacts..."
	@./clean_all.sh
	@echo "[MAKE] Clean complete."
