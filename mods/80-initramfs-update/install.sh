set -e                  # exit on error
set -o pipefail         # exit on pipeline error
set -u                  # treat unset variable as error

# Update initramfs — dual-track dracut and initramfs-tools
if command -v dracut >/dev/null 2>&1; then
    dracut --force --regenerate-all
elif command -v update-initramfs >/dev/null 2>&1; then
    update-initramfs -u -k all
else
    echo "ERROR: No initramfs generator (dracut or initramfs-tools) found!"
    exit 1
fi
judge "Update initramfs"