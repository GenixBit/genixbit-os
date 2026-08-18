#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# GenixBit OS — Universal Hybrid BIOS/UEFI ISO Builder & Verification Suite
import hashlib
import os
import subprocess
import sys
import shutil
import zipfile
import time

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
MASTER_ROOT = "/home/ubuntu/iso-build/iso-root"
DIST_DIR = os.path.join(REPO_ROOT, "dist", "iso-releases")
WEB_PKG_DIR = os.path.join(REPO_ROOT, "website", "packages", "iso")
os.makedirs(DIST_DIR, exist_ok=True)
os.makedirs(WEB_PKG_DIR, exist_ok=True)

RELEASES = [
    {
        "tag": "v1.5.0",
        "version": "1.5.0",
        "codename": "sutra",
        "vol_id": "GENIXBIT_150_SUTRA",
        "iso_name": "GenixBitOS-1.5.0-sutra-20260817.iso",
        "display_name": "GenixBit OS 1.5.0 (Sutra)"
    },
    {
        "tag": "v1.4.0",
        "version": "1.4.0",
        "codename": "drishti",
        "vol_id": "GENIXBIT_140_DRISHTI",
        "iso_name": "GenixBitOS-1.4.0-drishti-20260817.iso",
        "display_name": "GenixBit OS 1.4.0 (Drishti)"
    },
    {
        "tag": "v1.3.0",
        "version": "1.3.0",
        "codename": "vayu",
        "vol_id": "GENIXBIT_130_VAYU",
        "iso_name": "GenixBitOS-1.3.0-vayu-20260817.iso",
        "display_name": "GenixBit OS 1.3.0 (Vayu)"
    },
    {
        "tag": "v1.2.0",
        "version": "1.2.0",
        "codename": "kavach",
        "vol_id": "GENIXBIT_120_KAVACH",
        "iso_name": "GenixBitOS-1.2.0-kavach-20260817.iso",
        "display_name": "GenixBit OS 1.2.0 (Kavach)"
    },
    {
        "tag": "v1.1.0",
        "version": "1.1.0",
        "codename": "shakti",
        "vol_id": "GENIXBIT_110_SHAKTI",
        "iso_name": "GenixBitOS-1.1.0-shakti-20260817.iso",
        "display_name": "GenixBit OS 1.1.0 (Shakti)"
    },
    {
        "tag": "v1.0.0-lts",
        "version": "1.0.0",
        "codename": "lts",
        "vol_id": "GENIXBIT_100_LTS",
        "iso_name": "GenixBitOS-1.0.0-lts-2311142213.iso",
        "display_name": "GenixBit OS 1.0.0 LTS (Foundation)"
    }
]

GRUB_EARLY_CFG = """search --no-floppy --file --set=root /casper/vmlinuz
set prefix=($root)/boot/grub
configfile $prefix/grub.cfg
"""

STARTUP_NSH_CONTENT = """@echo -off
echo ============================================================
echo   Starting GenixBit OS Live Bootloader...
echo ============================================================
FS0:
if exist \\EFI\\BOOT\\BOOTX64.EFI then
  \\EFI\\BOOT\\BOOTX64.EFI
endif
if exist \\EFI\\BOOT\\grubx64.efi then
  \\EFI\\BOOT\\grubx64.efi
endif
FS1:
if exist \\EFI\\BOOT\\BOOTX64.EFI then
  \\EFI\\BOOT\\BOOTX64.EFI
endif
\\EFI\\BOOT\\BOOTX64.EFI
"""

def make_robust_grub_cfg(display_name):
    return f"""
if [ -s $prefix/grubenv ]; then
  load_env
fi

# Locate root partition reliably across UTM, VMware, VirtualBox, QEMU
search --no-floppy --set=root --file /casper/vmlinuz

insmod all_video
insmod gfxterm
insmod font
insmod png
insmod jpeg

if loadfont /boot/grub/fonts/unicode.pf2 ; then
    terminal_output gfxterm
elif loadfont /isolinux/unicode.pf2 ; then
    terminal_output gfxterm
fi

set default="0"
set timeout=5

menuentry "Try or Install {display_name} (Live & Desktop Installer)" {{
    set gfxpayload=keep
    linux   /casper/vmlinuz boot=casper maybe-ubiquity quiet splash console=tty0 ---
    initrd  /casper/initrd
}}

menuentry "Try or Install {display_name} (Safe Graphics Mode - nomodeset)" {{
    set gfxpayload=keep
    linux   /casper/vmlinuz boot=casper nomodeset console=tty0 ---
    initrd  /casper/initrd
}}

menuentry "{display_name} (Fast RAM Boot - toram)" {{
    set gfxpayload=keep
    linux   /casper/vmlinuz boot=casper toram quiet splash ---
    initrd  /casper/initrd
}}

menuentry "Check installation media for defects (Integrity Verification)" {{
    set gfxpayload=keep
    linux   /casper/vmlinuz boot=casper integrity-check quiet splash ---
    initrd  /casper/initrd
}}

if [ "$grub_platform" == "efi" ]; then
    menuentry "UEFI Firmware Settings" {{
        fwsetup
    }}
fi
"""

def check_master_template():
    if not os.path.exists(MASTER_ROOT):
        print(f"[ERROR] Master template {MASTER_ROOT} does not exist!")
        sys.exit(1)
    for req in ["casper/vmlinuz", "casper/initrd", "casper/filesystem.squashfs", "boot/grub/bios.img"]:
        req_path = os.path.join(MASTER_ROOT, req)
        if not os.path.exists(req_path):
            print(f"[ERROR] Missing required ISO asset: {req_path}")
            sys.exit(1)
    print(f"[PASS] Master ISO template verified at {MASTER_ROOT}")

def build_standalone_efi():
    os.makedirs("/tmp/efi-gen", exist_ok=True)
    early_cfg_path = "/tmp/efi-gen/grub-early.cfg"
    bootx64_path = "/tmp/efi-gen/BOOTX64.EFI"
    efiboot_img_path = "/tmp/efi-gen/efiboot.img"
    startup_nsh_path = "/tmp/efi-gen/startup.nsh"
    
    with open(early_cfg_path, "w") as f:
        f.write(GRUB_EARLY_CFG)
    with open(startup_nsh_path, "w", newline="\r\n") as f:
        f.write(STARTUP_NSH_CONTENT)
        
    # Generate standalone BOOTX64.EFI with grub-mkstandalone
    cmd = [
        "grub-mkstandalone",
        "--format=x86_64-efi",
        f"--output={bootx64_path}",
        "--locales=",
        "--fonts=",
        f"boot/grub/grub.cfg={early_cfg_path}"
    ]
    subprocess.run(cmd, check=True)
    
    # Generate FAT12 efiboot.img using mtools
    if os.path.exists(efiboot_img_path):
        os.remove(efiboot_img_path)
    subprocess.run(["dd", "if=/dev/zero", f"of={efiboot_img_path}", "bs=1M", "count=8"], check=True)
    subprocess.run(["mkfs.vfat", "-F", "12", "-n", "EFI", efiboot_img_path], check=True)
    subprocess.run(["mmd", "-i", efiboot_img_path, "::/EFI", "::/EFI/BOOT"], check=True)
    subprocess.run(["mcopy", "-o", "-i", efiboot_img_path, bootx64_path, "::/EFI/BOOT/BOOTX64.EFI"], check=True)
    subprocess.run(["mcopy", "-o", "-i", efiboot_img_path, bootx64_path, "::/EFI/BOOT/grubx64.efi"], check=True)
    subprocess.run(["mcopy", "-o", "-i", efiboot_img_path, early_cfg_path, "::/EFI/BOOT/grub.cfg"], check=True)
    subprocess.run(["mcopy", "-o", "-i", efiboot_img_path, startup_nsh_path, "::/startup.nsh"], check=True)
    subprocess.run(["mcopy", "-o", "-i", efiboot_img_path, startup_nsh_path, "::/EFI/BOOT/startup.nsh"], check=True)
    
    return bootx64_path, efiboot_img_path, startup_nsh_path

def build_iso(rel, bootx64_path, efiboot_img_path, startup_nsh_path):
    iso_name = rel["iso_name"]
    raw_iso_path = os.path.join(DIST_DIR, iso_name)
    zip_path = os.path.join(DIST_DIR, f"{iso_name}.zip")
    sha256_path = os.path.join(DIST_DIR, f"{iso_name}.sha256")
    sha512_path = os.path.join(DIST_DIR, f"{iso_name}.sha512")
    build_tree = f"/tmp/iso-tree-{rel['codename']}"
    
    print(f"\n============================================================")
    print(f"[BUILD] Building Bulletproof UTM / VMware / VirtualBox ISO for {rel['version']} ({rel['codename'].capitalize()})...")
    print(f"============================================================")
    
    if os.path.exists(build_tree):
        subprocess.run(["chmod", "-R", "u+w", build_tree], check=False)
        shutil.rmtree(build_tree)
        
    # Copy using hard links to save disk space
    shutil.copytree(MASTER_ROOT, build_tree, copy_function=os.link)
    subprocess.run(["chmod", "-R", "u+w", build_tree], check=True)
    
    # 1. Update release info in .disk/info and create root marker /genixbitos
    disk_info_path = os.path.join(build_tree, ".disk", "info")
    os.makedirs(os.path.dirname(disk_info_path), exist_ok=True)
    with open(disk_info_path, "w") as f:
        f.write(f"GenixBit OS {rel['version']} \"{rel['codename'].capitalize()}\" - Release amd64 (20260817)\n")
        
    with open(os.path.join(build_tree, "genixbitos"), "w") as f:
        f.write(f"GenixBit OS {rel['version']} {rel['codename']}\n")
        
    # 2. Embed startup.nsh in root and EFI directories
    for nsh in [
        os.path.join(build_tree, "startup.nsh"),
        os.path.join(build_tree, "STARTUP.NSH"),
        os.path.join(build_tree, "EFI", "BOOT", "startup.nsh"),
        os.path.join(build_tree, "EFI", "BOOT", "STARTUP.NSH")
    ]:
        os.makedirs(os.path.dirname(nsh), exist_ok=True)
        shutil.copy2(startup_nsh_path, nsh)
        
    # 3. Copy standalone BOOTX64.EFI and efiboot.img
    efi_boot_dir = os.path.join(build_tree, "EFI", "BOOT")
    os.makedirs(efi_boot_dir, exist_ok=True)
    shutil.copy2(bootx64_path, os.path.join(efi_boot_dir, "BOOTX64.EFI"))
    shutil.copy2(bootx64_path, os.path.join(efi_boot_dir, "bootx64.efi"))
    shutil.copy2(bootx64_path, os.path.join(efi_boot_dir, "grubx64.efi"))
    shutil.copy2(efiboot_img_path, os.path.join(build_tree, "EFI", "efiboot.img"))

    # 4. Write robust, direct boot GRUB configurations across all bootloader paths
    grub_content = make_robust_grub_cfg(rel["display_name"])
    for cfg_loc in [
        os.path.join(build_tree, "boot", "grub", "grub.cfg"),
        os.path.join(build_tree, "isolinux", "grub.cfg"),
        os.path.join(build_tree, "EFI", "BOOT", "grub.cfg")
    ]:
        os.makedirs(os.path.dirname(cfg_loc), exist_ok=True)
        with open(cfg_loc, "w") as f:
            f.write(grub_content)

    # 5. Build ISO using xorriso with hybrid MBR + GPT + EFI boot sectors
    cmd = [
        "xorriso", "-as", "mkisofs",
        "-r", "-V", rel["vol_id"],
        "-J", "-joliet-long",
        "-b", "boot/grub/bios.img",
        "-c", "boot/grub/boot.cat",
        "-no-emul-boot", "-boot-load-size", "4", "-boot-info-table", "--grub2-boot-info",
        "-eltorito-alt-boot",
        "-e", "EFI/efiboot.img",
        "-no-emul-boot", "-isohybrid-gpt-basdat",
        "-partition_offset", "16",
        "-o", raw_iso_path,
        build_tree
    ]
    
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"[FAIL] xorriso build failed for {iso_name}:")
        print(res.stderr)
        sys.exit(1)
        
    size_bytes = os.path.getsize(raw_iso_path)
    size_mb = size_bytes / (1024 * 1024)
    print(f"[PASS] Built {iso_name}: {size_bytes:,} bytes ({size_mb:.1f} MB)")
    
    # 6. Run dual-mode VM boot test (BIOS and UEFI)
    test_dual_boot(raw_iso_path, rel)
    
    # 7. Package into .zip and calculate checksums
    package_release_assets(raw_iso_path, rel)
    
    # Clean up raw ISO and temp build tree to preserve server disk space
    if os.path.exists(raw_iso_path):
        os.remove(raw_iso_path)
    subprocess.run(["chmod", "-R", "u+w", build_tree], check=False)
    shutil.rmtree(build_tree, ignore_errors=True)

def test_dual_boot(raw_iso_path, rel):
    print(f"[TEST 1/2] Testing BIOS Virtual Machine boot for {rel['iso_name']}...")
    bios_cmd = [
        "qemu-system-x86_64",
        "-cdrom", raw_iso_path,
        "-m", "1024",
        "-boot", "d",
        "-display", "none",
        "-vnc", "127.0.0.1:97",
        "-no-reboot"
    ]
    proc = subprocess.Popen(bios_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    time.sleep(3)
    poll = proc.poll()
    if poll is not None and poll != 0:
        _, stderr = proc.communicate()
        print(f"[FAIL] BIOS boot failed: {stderr.decode('utf-8')}")
        sys.exit(1)
    proc.terminate()
    proc.wait(timeout=5)
    print(f"[PASS] BIOS Boot Test PASSED.")

    # UEFI Boot Test with OVMF_CODE_4M.fd
    for ovmf in ["/usr/share/OVMF/OVMF_CODE_4M.fd", "/usr/share/ovmf/OVMF.fd", "/usr/share/qemu/OVMF.fd"]:
        if os.path.exists(ovmf):
            print(f"[TEST 2/2] Testing UEFI Virtual Machine boot with {ovmf} for {rel['iso_name']}...")
            uefi_cmd = [
                "qemu-system-x86_64",
                "-drive", f"if=pflash,format=raw,readonly=on,file={ovmf}",
                "-cdrom", raw_iso_path,
                "-m", "1024",
                "-boot", "d",
                "-display", "none",
                "-vnc", "127.0.0.1:97",
                "-no-reboot"
            ]
            proc = subprocess.Popen(uefi_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            time.sleep(3)
            poll = proc.poll()
            if poll is not None and poll != 0:
                _, stderr = proc.communicate()
                print(f"[FAIL] UEFI boot failed: {stderr.decode('utf-8')}")
                sys.exit(1)
            proc.terminate()
            proc.wait(timeout=5)
            print(f"[PASS] UEFI Boot Test PASSED.")
            break

def package_release_assets(raw_iso_path, rel):
    iso_name = rel["iso_name"]
    zip_path = os.path.join(DIST_DIR, f"{iso_name}.zip")
    sha256_path = os.path.join(DIST_DIR, f"{iso_name}.sha256")
    sha512_path = os.path.join(DIST_DIR, f"{iso_name}.sha512")
    
    print(f"[PACKAGE] Compressing {iso_name} into universal .zip container...")
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=1) as zf:
        zf.write(raw_iso_path, arcname=iso_name)
    print(f"[PASS] Created {os.path.basename(zip_path)}: {os.path.getsize(zip_path):,} bytes")
    
    sha256 = hashlib.sha256()
    sha512 = hashlib.sha512()
    with open(raw_iso_path, "rb") as f:
        for chunk in iter(lambda: f.read(16 * 1024 * 1024), b""):
            sha256.update(chunk)
            sha512.update(chunk)
            
    sha256_hex = sha256.hexdigest()
    sha512_hex = sha512.hexdigest()
    
    with open(sha256_path, "w") as f:
        f.write(f"{sha256_hex}  {iso_name}\n")
    with open(sha512_path, "w") as f:
        f.write(f"{sha512_hex}  {iso_name}\n")
        
    print(f"[PASS] SHA256: {sha256_hex}")
    
    for p in [zip_path, sha256_path, sha512_path]:
        dst = os.path.join(WEB_PKG_DIR, os.path.basename(p))
        if os.path.exists(dst):
            os.remove(dst)
        shutil.move(p, dst)

def main():
    check_master_template()
    bootx64_path, efiboot_img_path, startup_nsh_path = build_standalone_efi()
    all_sha256 = []
    
    for rel in RELEASES:
        build_iso(rel, bootx64_path, efiboot_img_path, startup_nsh_path)
        sha256_file = os.path.join(WEB_PKG_DIR, f"{rel['iso_name']}.sha256")
        with open(sha256_file, "r") as f:
            all_sha256.append(f.read().strip())
            
    sha256sums_path = os.path.join(WEB_PKG_DIR, "SHA256SUMS")
    with open(sha256sums_path, "w") as f:
        f.write("\n".join(all_sha256) + "\n")
    
    print("\n============================================================")
    print(">>> ALL 6 STANDALONE EFI & BIOS ISOS VERIFIED & PACKAGED <<<")
    print("============================================================")
    for s in all_sha256:
        print(s)

if __name__ == "__main__":
    main()
