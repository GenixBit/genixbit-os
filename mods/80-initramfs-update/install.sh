#!/bin/bash
set -e
set -o pipefail
set -u

print_ok "Updating initramfs for LIVE ISO..."

# =========================================================
# LIVE ISO BUILD SPECIFIC LOGIC
# We MUST use initramfs-tools here because Dracut cannot
# boot an Ubuntu 'casper' Live ISO natively.
# =========================================================

# Ensure SOURCE_DATE_EPOCH is exported if present in environment
if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
    export SOURCE_DATE_EPOCH
fi

if command -v update-initramfs >/dev/null 2>&1; then
    # Clean up non-deterministic configs and files before generating initramfs
    print_ok "Cleaning up non-reproducible config comments and files..."
    if [ -f /etc/mdadm/mdadm.conf ]; then
        sed -i '/auto-generated on/d' /etc/mdadm/mdadm.conf
    fi
    rm -f /etc/ssl/certs/ssl-cert-snakeoil.pem || true
    rm -f /etc/ssl/private/ssl-cert-snakeoil.key || true
    find /etc/ssl/certs -type l 2>/dev/null | while read -r symlink; do
        if [ ! -e "$symlink" ] || [[ "$(readlink "$symlink")" == *"ssl-cert-snakeoil"* ]]; then
            rm -f "$symlink"
        fi
    done
    rm -f /root/.wget-hsts || true
    print_ok "Cleanup completed."

    print_ok "Using initramfs-tools to ensure 'casper' live-boot capability..."
    update-initramfs -u -k all
else
    print_error "ERROR: initramfs-tools is missing! Casper live boot will fail."
    exit 1
fi

judge "Update initramfs"
