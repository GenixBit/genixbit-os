# GenixBit OS Authenticated Guest Validation Architecture

## Overview
This document specifies the authenticated guest-control mechanism and verification framework for GenixBit OS 0.3.0-alpha release gate validation.

## Primary Authenticated Guest Channel
The primary guest-control mechanism uses **SSH over localhost port forwarding** (or a dedicated `virtio-serial` QEMU Guest Agent socket). Unauthenticated serial-log parsing or QMP monitor socket pinging is prohibited for arbitrary guest command execution.

### Key Components:
1. **Authentication Method**:
   - Ephemeral SSH keypair generated at runtime (or test credentials scoped strictly to the ephemeral test VM environment).
   - No hardcoded private keys or passwords committed to the git repository.
2. **Port Allocation**:
   - QEMU user network mode forwards a unique host port to guest port 22:
     `-netdev user,id=net0,hostfwd=tcp::<port>-:22`
3. **Guest Readiness Verification** ([`tools/vm/wait-for-guest.sh`](file:///Users/manojnandanwar/genixbit-os/tools/vm/wait-for-guest.sh)):
   - Verifies VM process is running.
   - Establishes SSH connection to guest on the forwarded port.
   - Executes readiness command inside guest:
     `printf 'GENIXBIT_GUEST_READY_%s\n' "$RUN_TOKEN"`
   - Verifies the run-specific token matches before declaring the guest ready.
4. **Observed Command Execution** ([`tools/vm/guest-command.sh`](file:///Users/manojnandanwar/genixbit-os/tools/vm/guest-command.sh)):
   - Runs requested commands inside the guest over authenticated SSH or dedicated QGA socket.
   - Captures exact command, start/completion timestamps, exit code, stdout file, stderr file, and stdout/stderr SHA-256 digests.
5. **Additive Disk-Boot Verification**:
   - When `--verify-disk-boot` is enabled, executes requested commands AND verifies root filesystem source inside the guest:
     `findmnt -n -o SOURCE,FSTYPE /`
     `lsblk -o NAME,TYPE,FSTYPE,MOUNTPOINTS`
     `cat /proc/cmdline`
   - Confirms root `/` is mounted from regular disk partitions (e.g. `/dev/vda1`, `/dev/sda1`) and NOT live media (`iso9660`, `/dev/sr0`, `casper`).
6. **Reboot & Shutdown Handling**:
   - Fail-closed execution (`sudo systemctl reboot` or `sudo systemctl poweroff`).
   - Disconnects gracefully, waits for VM to cycle, authenticates again, and verifies new run-specific token.
7. **Secret Cleanup**:
   - Ephemeral keys and tokens deleted automatically on script exit or trap cleanup.
