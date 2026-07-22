#!/bin/bash

#==========================
# Set up the environment
#==========================
set -e                  # exit on error
set -o pipefail         # exit on pipeline error
set -u                  # treat unset variable as error
umask 022               # ensure built system files and keyrings are world-readable
export SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# Define SOURCE_DATE_EPOCH if not already defined (fall back to latest git commit time or current time)
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct 2>/dev/null || date +%s)}"

source $SCRIPT_DIR/shared.sh
source $SCRIPT_DIR/args.sh

function bind_signal() {
    print_ok "Bind signal..."
    trap umount_on_exit EXIT
    judge "Bind signal"
}

function clean() {
    print_ok "Cleaning up previous build..."
    sudo umount new_building_os/sys || sudo umount -lf new_building_os/sys || true
    sudo umount new_building_os/proc || sudo umount -lf new_building_os/proc || true
    sudo umount new_building_os/dev || sudo umount -lf new_building_os/dev || true
    sudo umount new_building_os/run || sudo umount -lf new_building_os/run || true
    sudo rm -rf new_building_os image || true
    judge "Clean up build artifacts"
}

function download_base_system() {
    print_ok "Creating new_building_os directory..."
    sudo mkdir -p new_building_os
    judge "Create build directory"

    print_ok "Calling debootstrap to download base debian system..."
    sudo debootstrap  --arch=amd64 --variant=minbase --include=ca-certificates,wget,dbus $TARGET_UBUNTU_VERSION new_building_os $APT_SOURCE
    judge "Download base system"
}

function mount_folders() {
    print_ok "Reloading systemd daemon..."
    if command -v systemctl > /dev/null 2>&1 && systemctl is-system-running > /dev/null 2>&1; then
        sudo systemctl daemon-reload
        judge "Reload systemd daemon"
    else
        print_ok "Skipping systemctl daemon-reload (systemd not running; container build)"
    fi

    print_ok "Mounting /dev /run from host to build dir..."
    sudo mount --bind /dev new_building_os/dev
    sudo mount --bind /run new_building_os/run
    judge "Mount /dev /run"

    print_ok "Mounting /proc /sys /dev/pts within chroot..."
    sudo chroot new_building_os mount none -t proc /proc
    sudo chroot new_building_os mount none -t sysfs /sys
    sudo chroot new_building_os mount none -t devpts /dev/pts
    judge "Mount /proc /sys /dev/pts"

    print_ok "Copying mods to chroot /root/mods..."
    sudo cp -r $SCRIPT_DIR/mods new_building_os/root/mods
    sudo cp $SCRIPT_DIR/args.sh   new_building_os/root/mods/args.sh
    sudo cp $SCRIPT_DIR/shared.sh new_building_os/root/mods/shared.sh

    print_ok "Copying pre-compiled branding packages to chroot /root/debs..."
    sudo mkdir -p new_building_os/root/debs
    sudo cp $SCRIPT_DIR/packages/build-debs/*.deb new_building_os/root/debs/
}

function setup_apt() {
    print_ok "Setting up Ubuntu apt sources in chroot..."
    sudo mkdir -p new_building_os/etc/apt/sources.list.d
    sudo tee new_building_os/etc/apt/sources.list.d/ubuntu.sources > /dev/null <<EOF
Types: deb
URIs: $APT_SOURCE
Suites: $TARGET_UBUNTU_VERSION
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: $APT_SOURCE
Suites: $TARGET_UBUNTU_VERSION-updates
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: $APT_SOURCE
Suites: $TARGET_UBUNTU_VERSION-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: $APT_SOURCE
Suites: $TARGET_UBUNTU_VERSION-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
    judge "Set up Ubuntu apt sources"

    # Remove stale legacy-format sources.list (debootstrap artifact).
    # Ubuntu 24.04+ uses deb822 .sources files in sources.list.d/ instead.
    sudo rm -f new_building_os/etc/apt/sources.list

    print_ok "Setting up AnduinOS APKG apt source in chroot..."

    local keyring_path="new_building_os/usr/share/keyrings/anduinos-archive-keyring.gpg"
    local cert_url="$APKG_SERVER/artifacts/certs/$APKG_CERT_NAME"

    print_ok "Downloading GPG keyring from $cert_url ..."
    sudo mkdir -p new_building_os/usr/share/keyrings
    curl -sL "$cert_url" | sed '1s/^\xEF\xBB\xBF//' | gpg --dearmor | sudo tee "$keyring_path" > /dev/null
    judge "Download and dearmor keyring"

    print_ok "Generating anduinos.sources for $APKG_SERVER (suite: $TARGET_UBUNTU_VERSION-addon)..."
    sudo mkdir -p new_building_os/etc/apt/sources.list.d
    sudo tee new_building_os/etc/apt/sources.list.d/anduinos.sources > /dev/null <<EOF
Types: deb
URIs: $APKG_SERVER/artifacts/anduinos/
Suites: $TARGET_UBUNTU_VERSION-addon
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/anduinos-archive-keyring.gpg
EOF
    judge "Generate sources"

    print_ok "Enabling apt recommends in chroot..."
    echo 'APT::Install-Recommends "true";' | sudo tee new_building_os/etc/apt/apt.conf.d/99-enable-recommends > /dev/null
    judge "Enable apt recommends"

    print_ok "Running apt update in chroot..."
    sudo chroot new_building_os apt update
    judge "Apt update in chroot"

    # Upgrade base system BEFORE mods run.  Swap packages (mod 01)
    # must not be visible to this upgrade — apt would try to
    # "normalize" them back to Ubuntu's lower version and fail.
    print_ok "Upgrading base system packages..."
    sudo chroot new_building_os apt -y upgrade
    judge "Upgrade base system"
}

function run_chroot() {
    print_ok "Running install_all_mods.sh in new_building_os..."
    print_warn "============================================"
    print_warn "   The following will run in chroot ENV!"
    print_warn "============================================"
    sudo env SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH chroot new_building_os /usr/bin/env DEBIAN_FRONTEND=${DEBIAN_FRONTEND:-readline} SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH /root/mods/install_all_mods.sh -
    print_warn "============================================"
    print_warn "   chroot ENV execution completed!"
    print_warn "============================================"
    judge "Run install_all_mods.sh in new_building_os"

    print_ok "Sleeping for 5 seconds to allow chroot to exit cleanly..."
    sleep 5
}

function umount_folders() {
    print_ok "Cleaning mods from chroot /root/mods..."
    sudo rm -rf new_building_os/root/mods
    judge "Clean up chroot /root/mods"

    print_ok "Cleaning packages from chroot /root/debs..."
    sudo rm -rf new_building_os/root/debs
    judge "Clean up chroot /root/debs"

    print_ok "Unmounting /proc /sys /dev/pts within chroot..."
    sudo chroot new_building_os umount /dev/pts || sudo chroot new_building_os umount -lf /dev/pts || true
    sudo chroot new_building_os umount /sys || sudo chroot new_building_os umount -lf /sys || true
    sudo chroot new_building_os umount /proc || sudo chroot new_building_os umount -lf /proc || true
    judge "Unmount /proc /sys /dev/pts"

    print_ok "Unmounting /dev /run outside of chroot..."
    sudo umount new_building_os/dev || sudo umount -lf new_building_os/dev || true
    sudo umount new_building_os/run || sudo umount -lf new_building_os/run || true
    judge "Unmount /dev /run"
}

function build_iso() {
    print_ok "Building ISO image..."

    print_ok "Creating image directory..."
    sudo rm -rf image
    mkdir -p image/{casper,isolinux,.disk}
    judge "Create image directory"

    # copy kernel files
    print_ok "Copying kernel files as /casper/vmlinuz, /casper/initrd and /casper/initrd.gz..."
    # Resolve the distro-maintained symlinks — they always point to the
    # current kernel, so we never pick a stale one left behind by apt.
    sudo chmod 755 new_building_os 2>/dev/null || true
    sudo chmod -R a+rX new_building_os/boot 2>/dev/null || true
    REAL_VMLINUZ=$(sudo readlink -f new_building_os/vmlinuz 2>/dev/null)
    [ -n "$REAL_VMLINUZ" ] && [ -f "$REAL_VMLINUZ" ] || REAL_VMLINUZ=$(sudo readlink -f new_building_os/boot/vmlinuz 2>/dev/null)
    REAL_INITRD=$(sudo readlink -f new_building_os/initrd.img 2>/dev/null)
    [ -n "$REAL_INITRD" ] && [ -f "$REAL_INITRD" ] || REAL_INITRD=$(sudo readlink -f new_building_os/boot/initrd.img 2>/dev/null)
    if [ -z "$REAL_VMLINUZ" ] || [ ! -f "$REAL_VMLINUZ" ]; then
        print_error "No kernel found via vmlinuz symlink in new_building_os/"
        exit 1
    fi
    if [ -z "$REAL_INITRD" ] || [ ! -f "$REAL_INITRD" ]; then
        print_error "No initrd found via initrd.img symlink in new_building_os/"
        exit 1
    fi
    sudo cp "$REAL_VMLINUZ" image/casper/vmlinuz
    sudo cp "$REAL_INITRD" image/casper/initrd
    sudo cp "$REAL_INITRD" image/casper/initrd.gz
    judge "Copy kernel files"

    print_ok "Generating grub.cfg..."
    touch image/$TARGET_NAME
    cp $SCRIPT_DIR/args.sh image/$TARGET_NAME
    judge "Copy build args to disk"

    # Configurations are setup in new_building_os/usr/share/initramfs-tools/scripts/casper-bottom/25configure_init
    TRY_TEXT="Try or Install $TARGET_BUSINESS_NAME"
    TOGO_TEXT="$TARGET_BUSINESS_NAME To Go (Persistent on USB)"

    # Build locale submenu entries for Try mode.
    # Each entry also derives a best-guess timezone so the live session
    # clock matches the user's region, not hardcoded Los Angeles.
    _TRY_LOCALE_ENTRIES=""
    while IFS="|" read -r _code _label; do
        [ -z "$_code" ] && continue
        [ -z "$_label" ] && continue

        # locale -> timezone best-guess mapping
        case "${_code}" in
            en_US) _tz="America/New_York" ;;
            en_GB) _tz="Europe/London" ;;
            zh_CN) _tz="Asia/Shanghai" ;;
            zh_TW) _tz="Asia/Taipei" ;;
            zh_HK) _tz="Asia/Hong_Kong" ;;
            ja_JP) _tz="Asia/Tokyo" ;;
            ko_KR) _tz="Asia/Seoul" ;;
            vi_VN) _tz="Asia/Ho_Chi_Minh" ;;
            th_TH) _tz="Asia/Bangkok" ;;
            de_DE) _tz="Europe/Berlin" ;;
            fr_FR) _tz="Europe/Paris" ;;
            es_ES) _tz="Europe/Madrid" ;;
            ru_RU) _tz="Europe/Moscow" ;;
            it_IT) _tz="Europe/Rome" ;;
            pt_PT) _tz="Europe/Lisbon" ;;
            pt_BR) _tz="America/Sao_Paulo" ;;
            ar_SA) _tz="Asia/Riyadh" ;;
            nl_NL) _tz="Europe/Amsterdam" ;;
            sv_SE) _tz="Europe/Stockholm" ;;
            pl_PL) _tz="Europe/Warsaw" ;;
            tr_TR) _tz="Europe/Istanbul" ;;
            ro_RO) _tz="Europe/Bucharest" ;;
            da_DK) _tz="Europe/Copenhagen" ;;
            uk_UA) _tz="Europe/Kiev" ;;
            id_ID) _tz="Asia/Jakarta" ;;
            fi_FI) _tz="Europe/Helsinki" ;;
            hi_IN) _tz="Asia/Kolkata" ;;
            el_GR) _tz="Europe/Athens" ;;
            *)      _tz="America/Los_Angeles" ;;
        esac

        _TRY_LOCALE_ENTRIES="$_TRY_LOCALE_ENTRIES
    menuentry \"$_label\" {
        set gfxpayload=keep
        linux   /casper/vmlinuz boot=casper locale=${_code}.UTF-8 timezone=${_tz} systemd.timezone=${_tz} nopersistent quiet splash ---
        initrd  /casper/initrd
    }"
    done <<< "$SUPPORTED_LOCALES"

    # Copy system unicode.pf2 so GRUB can render CJK/Arabic/Thai labels.
    # Without loadfont, GRUB defaults to an ASCII-only built-in font.
    # Placed in both paths: isolinux (BIOS) and boot/grub/fonts (UEFI standard).
    print_ok "Preparing GRUB unicode font (for CJK)..."
    mkdir -p image/isolinux image/boot/grub/fonts
    cp /usr/share/grub/unicode.pf2 image/isolinux/unicode.pf2
    cp /usr/share/grub/unicode.pf2 image/boot/grub/fonts/unicode.pf2
    judge "Prepare GRUB unicode font"

    cat << EOF > image/isolinux/grub.cfg

search --set=root --file /$TARGET_NAME

insmod all_video
insmod gfxterm
insmod font
if loadfont /boot/grub/fonts/unicode.pf2 ; then
    terminal_output gfxterm
elif loadfont /isolinux/unicode.pf2 ; then
    terminal_output gfxterm
fi

set default="0"
set timeout=10

submenu "$TRY_TEXT" {
$_TRY_LOCALE_ENTRIES
}

submenu "Advanced Options..." {
    menuentry "$TRY_TEXT (Safe Graphics)" {
        set gfxpayload=keep
        linux   /casper/vmlinuz boot=casper nopersistent nomodeset ---
        initrd  /casper/initrd
    }
    menuentry "$TOGO_TEXT" {
        set gfxpayload=keep
        linux   /casper/vmlinuz boot=casper persistent quiet splash ---
        initrd  /casper/initrd
    }
    menuentry "Check installation media for defects (Integrity Check)" {
        set gfxpayload=keep
        linux   /casper/vmlinuz boot=casper integrity-check quiet splash ---
        initrd  /casper/initrd
    }
}

if [ "\$grub_platform" == "efi" ]; then
    menuentry "Boot from next volume" {
        exit 1
    }
    menuentry "UEFI Firmware Settings" {
        fwsetup
    }
fi
EOF
    judge "Generate grub.cfg"


    # generate manifest
    print_ok "Generating manifes for filesystem..."
    sudo chroot new_building_os dpkg-query -W --showformat='${Package} ${Version}\n' | sudo tee image/casper/filesystem.manifest >/dev/null 2>&1
    judge "Generate manifest for filesystem"

    print_ok "Generating manifest for filesystem-desktop..."
    sudo cp -v image/casper/filesystem.manifest image/casper/filesystem.manifest-desktop
    for pkg in $TARGET_PACKAGE_REMOVE; do
        sudo sed -i "/^$pkg /d" image/casper/filesystem.manifest-desktop
    done
    judge "Generate manifest for filesystem-desktop"

    print_ok "Compressing rootfs as squashfs on /casper/filesystem.squashfs..."
    sudo env -u SOURCE_DATE_EPOCH mksquashfs new_building_os image/casper/filesystem.squashfs \
        -noappend -no-duplicates -no-recovery \
        -mkfs-time $SOURCE_DATE_EPOCH -inode-time $SOURCE_DATE_EPOCH \
        -wildcards -b 1M \
        -comp zstd -Xcompression-level 19 \
        -e "var/cache/apt/archives/*" \
        -e "tmp/*" \
        -e "tmp/.*" \
        -e "swapfile"
    judge "Compress rootfs"

    print_ok "Verifying the integrity of filesystem.squashfs..."
    if sudo unsquashfs -s image/casper/filesystem.squashfs; then
        print_ok "Verification successful. The file appears to be valid."
    else
        print_error "Verification FAILED! The squashfs file is likely corrupt."
        exit 1
    fi
    
    print_ok "Generating filesystem.size on /casper/filesystem.size..."
    sudo find new_building_os -type f -printf "%s\n" 2>/dev/null | awk '{s+=$1} END {printf "%s", s}' > image/casper/filesystem.size
    judge "Generate filesystem.size"

    print_ok "Generating README.diskdefines..."
    cat << EOF > image/README.diskdefines
#define DISKNAME  Try $TARGET_BUSINESS_NAME
#define TYPE  binary
#define TYPEbinary  1
#define ARCH  amd64
#define ARCHamd64  1
#define DISKNUM  1
#define DISKNUM1  1
#define TOTALNUM  0
#define TOTALNUM0  1
EOF
    judge "Generate README.diskdefines"

    DATE=$(date -u -d "@$SOURCE_DATE_EPOCH" +"%y%m%d%H%M" 2>/dev/null || date -u -r "$SOURCE_DATE_EPOCH" +"%y%m%d%H%M")
    cat << EOF > image/README.md
# GenixBit OS $TARGET_BUILD_VERSION

GenixBit OS is an AI-first, developer-focused Ubuntu-based Linux distribution maintained by GenixBit Labs Private Limited. It is currently based on Ubuntu and AnduinOS 2.

This image is built with the following configurations:

- **Version**: $TARGET_BUILD_VERSION
- **Date**: $DATE

GenixBit OS is distributed under the GNU General Public License v3 (GPLv3). Source code, licensing details, and upstream attribution are available in the project repository: https://github.com/GenixBit/genixbit-os

## Verification

To verify the integrity of the image, calculate the MD5 checksum of the media files and compare against \`md5sum.txt\`:

\`\`\`bash
md5sum -c md5sum.txt | grep -v 'OK'
\`\`\`

If no error lines are printed, the installation media is intact.

## Booting

Insert the installation media and boot your system. Select the USB drive from your system's boot selection menu (F12 or option key depending on your hardware).

## Source & Documentation

For repository source code, development updates, and upstream attribution details, please visit:
https://github.com/GenixBit/genixbit-os
EOF

    pushd image
    print_ok "Creating EFI boot image on /isolinux/efiboot.img..."
    (
        cd isolinux && \
        dd if=/dev/zero of=efiboot.img bs=1M count=10 && \
        sudo mkfs.vfat --invariant -i 2e24ec82 efiboot.img && \

        # Build self-contained EFI binary with grub-mkstandalone.
        # grub-install cannot determine the canonical path of the overlay
        # filesystem used by Docker, so we bypass it entirely and use
        # grub-mkstandalone to produce a relocatable BOOTX64.EFI directly.
        mkdir -p efi_staging/EFI/BOOT && \
        sudo env SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH grub-mkstandalone \
            --format=x86_64-efi \
            --output=efi_staging/EFI/BOOT/BOOTX64.EFI \
            --locales="" \
            --fonts="" \
            "boot/grub/grub.cfg=grub.cfg" && \

        # Clamp modification time of the generated EFI executable to achieve reproducibility
        sudo touch -d "@$SOURCE_DATE_EPOCH" efi_staging/EFI/BOOT/BOOTX64.EFI && \

        # Inject EFI binary into the FAT image using mtools (no loop mount).
        sudo env SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH mmd  -i efiboot.img ::/EFI && \
        sudo env SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH mmd  -i efiboot.img ::/EFI/BOOT && \
        sudo env SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH mcopy -i efiboot.img efi_staging/EFI/BOOT/BOOTX64.EFI ::/EFI/BOOT/ && \
        sudo rm -rf efi_staging
    )
    judge "Create EFI boot image"

    print_ok "Creating BIOS boot image on /isolinux/bios.img..."
    grub-mkstandalone \
        --format=i386-pc \
        --output=isolinux/core.img \
        --install-modules="linux16 linux normal iso9660 biosdisk memdisk search tar ls font gfxterm all_video" \
        --modules="linux16 linux normal iso9660 biosdisk search font gfxterm all_video" \
        --locales="" \
        --fonts="" \
        "boot/grub/grub.cfg=isolinux/grub.cfg"
    judge "Create BIOS boot image"

    print_ok "Creating hybrid boot image on /isolinux/bios.img..."
    cat /usr/lib/grub/i386-pc/cdboot.img isolinux/core.img > isolinux/bios.img
    judge "Create hybrid boot image"

    print_ok "Creating .disk/info..."
    DISK_DATE=$(date -u -d "@$SOURCE_DATE_EPOCH" +%Y%m%d 2>/dev/null || date -u -r "$SOURCE_DATE_EPOCH" +%Y%m%d)
    echo "$TARGET_BUSINESS_NAME $TARGET_BUILD_VERSION $TARGET_UBUNTU_VERSION - Release amd64 ($DISK_DATE)" | sudo tee .disk/info
    judge "Create .disk/info"

    print_ok "Creating md5sum.txt..."
    sudo /bin/bash -c "(find . -type f -print0 | xargs -0 md5sum | grep -v -e 'md5sum.txt' -e 'bios.img' -e 'efiboot.img' > md5sum.txt)"
    judge "Create md5sum.txt"

    print_ok "Clamping file timestamps in image directory..."
    sudo find . -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
    judge "Clamp file timestamps"

    print_ok "Creating iso image on $SCRIPT_DIR/$TARGET_NAME.iso..."
    XORRISO_DATE=$(date -u -d "@$SOURCE_DATE_EPOCH" +"%Y%m%d%H%M%S00" 2>/dev/null || date -u -r "$SOURCE_DATE_EPOCH" +"%Y%m%d%H%M%S00")
    sudo env SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH xorriso \
        -as mkisofs \
        -r -J \
        -iso-level 3 \
        -full-iso9660-filenames \
        --modification-date="$XORRISO_DATE" \
        -volid "$TARGET_NAME" \
        -eltorito-boot boot/grub/bios.img \
            -no-emul-boot \
            -boot-load-size 4 \
            -boot-info-table \
            --eltorito-catalog boot/grub/boot.cat \
            --grub2-boot-info \
            --grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img \
        -eltorito-alt-boot \
            -e EFI/efiboot.img \
            -no-emul-boot \
            -append_partition 2 0xef isolinux/efiboot.img \
        -output "$SCRIPT_DIR/$TARGET_NAME.iso" \
        -m "isolinux/efiboot.img" \
        -m "isolinux/bios.img" \
        -graft-points \
            "/EFI/efiboot.img=isolinux/efiboot.img" \
            "/boot/grub/grub.cfg=isolinux/grub.cfg" \
            "/boot/grub/bios.img=isolinux/bios.img" \
            .

    judge "Create iso image"

    print_ok "Moving iso image to $SCRIPT_DIR/dist/$TARGET_BUSINESS_NAME-$TARGET_BUILD_VERSION-$DATE.iso..."
    mkdir -p "$SCRIPT_DIR/dist"
    mv "$SCRIPT_DIR/$TARGET_NAME.iso" "$SCRIPT_DIR/dist/$TARGET_BUSINESS_NAME-$TARGET_BUILD_VERSION-$DATE.iso"
    judge "Move iso image"

    print_ok "Generating sha256 checksum..."
    HASH=$(sha256sum "$SCRIPT_DIR/dist/$TARGET_BUSINESS_NAME-$TARGET_BUILD_VERSION-$DATE.iso" | cut -d ' ' -f 1)
    echo "SHA256: $HASH" > "$SCRIPT_DIR/dist/$TARGET_BUSINESS_NAME-$TARGET_BUILD_VERSION-$DATE.sha256"
    judge "Generate sha256 checksum"

    popd
}

function umount_on_exit() {
    sleep 2
    print_ok "Umount before exit..."
    sudo umount $SCRIPT_DIR/new_building_os/sys || sudo umount -lf $SCRIPT_DIR/new_building_os/sys || true
    sudo umount $SCRIPT_DIR/new_building_os/proc || sudo umount -lf $SCRIPT_DIR/new_building_os/proc || true
    sudo umount $SCRIPT_DIR/new_building_os/dev || sudo umount -lf $SCRIPT_DIR/new_building_os/dev || true
    sudo umount $SCRIPT_DIR/new_building_os/run || sudo umount -lf $SCRIPT_DIR/new_building_os/run || true
    judge "Umount before exit"
}

# =============   main  ================
cd $SCRIPT_DIR
bind_signal
clean
print_ok "Building branding packages..."
bash tools/validation/build-branding-packages.sh
download_base_system
mount_folders
setup_apt
run_chroot
umount_folders
build_iso
echo "$0 - Initial build is done!"
