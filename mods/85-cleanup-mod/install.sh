set -e                  # exit on error
set -o pipefail         # exit on pipeline error
set -u                  # treat unset variable as error

# Clean up root home
print_ok "Cleaning up /root/..."
rm -f /root/.config/mimeapps.list || true
rm -rf /root/.local/share/gnome-shell/extensions || true
rm -rf /root/.cache || true
judge "Clean up /root/"

# Clean up apt cache
print_ok "Cleaning up apt cache..."
find /var/cache/apt/archives -mindepth 1 -delete 2>/dev/null || true
rm -f /var/cache/apt/pkgcache.bin /var/cache/apt/srcpkgcache.bin || true
judge "Clean up apt cache"

# Clean up apt lists (save ~50-80MB in the squashfs; the installed system
# will re-fetch them on first apt update anyway)
print_ok "Cleaning up apt lists..."
find /var/lib/apt/lists -mindepth 1 -maxdepth 1 ! -name 'lock' ! -name 'partial' -delete 2>/dev/null || true
judge "Clean up apt lists"

# Clean up log files
print_ok "Cleaning up log files..."
find /var/log -mindepth 1 -delete 2>/dev/null || true
judge "Clean up log files"

# Truncate machine id
print_ok "Truncating machine id..."
truncate -s 0 /etc/machine-id || true
truncate -s 0 /var/lib/dbus/machine-id || true
judge "Truncate machine id"

# Remove timezone files (systemd.timezone= on kernel cmdline sets them at boot)
print_ok "Removing timezone files..."
rm -f /etc/localtime /etc/timezone || true
judge "Remove timezone files"

# Clean bash history and temp files
print_ok "Removing bash history, temporary files, and build logs..."
find /tmp -mindepth 1 -delete 2>/dev/null || true
rm -f ~/.bash_history 2>/dev/null || true
rm -f /root/.wget-hsts || true
rm -f /etc/ssl/certs/ssl-cert-snakeoil.pem || true
rm -f /etc/ssl/private/ssl-cert-snakeoil.key || true
find /etc/ssl/certs -type l 2>/dev/null | while read -r symlink; do
    if [ ! -e "$symlink" ] || [[ "$(readlink "$symlink")" == *"ssl-cert-snakeoil"* ]]; then
        rm -f "$symlink"
    fi
done
export HISTSIZE=0
judge "Remove bash history, temporary files, and build logs"

# Remove usr-is-merged folders
print_ok "Removing usr-is-merged folders..."
rm -rf /bin.usr-is-merged /lib.usr-is-merged /sbin.usr-is-merged || true
judge "Remove usr-is-merged folders"
