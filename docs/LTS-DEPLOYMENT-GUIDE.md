# GenixBit OS 1.0.0 LTS — Complete Deployment & Operations Guide

This guide provides end-to-end instructions for building, validating, installing, running local AI workloads, and deploying web services on **GenixBit OS 1.0.0 LTS**.

---

## 1. System Requirements

### Host Build Environment
- **OS**: Ubuntu 24.04+ or Debian 12+ (x86_64 / amd64)
- **CPU**: 4+ cores recommended
- **RAM**: 8 GB minimum (16 GB recommended for squashfs compression)
- **Disk**: 30 GB free space
- **Packages**: `debootstrap`, `squashfs-tools`, `xorriso`, `mtools`, `dosfstools`, `grub-pc-bin`, `grub-efi-amd64-bin`, `dpkg-dev`

### Target Machine (Bare-Metal / VM)
- **Processor**: 64-bit x86_64 Dual-Core or higher
- **RAM**: 4 GB minimum (8 GB+ recommended for local 2B-7B AI models)
- **Storage**: 25 GB minimum SSD/NVMe storage
- **Graphics / Accelerator**: 
  - NVIDIA GPU with CUDA compute 6.0+ (optional for GPU acceleration)
  - AMD GPU with ROCm support (optional)
  - Intel Arc / Xe Graphics with SYCL (optional)
  - CPU AVX2/AVX-512 fallback automatically enabled

---

## 2. Building the ISO Image

To compile a bit-for-bit reproducible ISO image:

```bash
# Clone the repository
git clone https://github.com/GenixBit/genixbit-os.git
cd genixbit-os

# Standardize and build branding packages
python3 tools/build-phase4-debs.py

# Run the rootfs build and ISO assembler
sudo ./build.sh
```

Output ISO and SHA256 checksums will be placed in the `dist/` directory:
- `dist/GenixBitOS-1.0.0-lts-<TIMESTAMP>.iso`
- `dist/GenixBitOS-1.0.0-lts-<TIMESTAMP>.sha256`

---

## 3. ISO Installation & Booting

### Checksum Verification
```bash
sha256sum GenixBitOS-1.0.0-lts-2311142213.iso
# Expected: 229b3f70f94d0ced3a3d33116a64a0f5a8c2a339070443e1d023938739873ce6
```

### Flashing to USB
```bash
sudo dd if=GenixBitOS-1.0.0-lts-2311142213.iso of=/dev/sdX bs=4M status=progress conv=fdatasync
```

### Running in QEMU / KVM Virtual Machine
```bash
# Create a 30 GB test disk
qemu-img create -f qcow2 genixbit-disk.qcow2 30G

# Launch VM with UEFI, 4 vCPUs, and 8 GB RAM
qemu-system-x86_64 \
    -m 8192 \
    -smp 4 \
    -enable-kvm \
    -cpu host \
    -drive file=genixbit-disk.qcow2,if=virtio \
    -cdrom GenixBitOS-1.0.0-lts-2311142213.iso \
    -boot d \
    -net nic,model=virtio -net user
```

---

## 4. Local AI Runtime & Developer Agents

GenixBit OS includes an integrated local AI runtime service designed for offline and developer agent workflows:

### A. Starting the AI Runtime Service
```bash
# Enable and start background systemd service
sudo systemctl enable --now genixbit-ai-proxy

# Check service status
sudo systemctl status genixbit-ai-proxy
```

The runtime exposes standard OpenAI-compatible and Ollama-compatible endpoints on `127.0.0.1:11434`:
- `GET  /health`
- `GET  /v1/models`
- `POST /v1/chat/completions` (supports streaming SSE)
- `POST /v1/embeddings`

### B. Managing Models with GenixBit AI Center
```bash
# List curated model catalog and resource requirements
genixbit-ai-center list

# Check local runtime health & active accelerator
genixbit-ai-center status

# Test local inference
genixbit-ai-center run --model gemma-3-2b-it --prompt "Write a Python script to monitor system load."
```

### C. Hardware & GPU Diagnostics
```bash
# Run automatic multi-vendor GPU and RAM detection
genixbit-gpu-diag
```

### D. Connecting Developer Agents
Connect your favorite IDEs and autonomous agent frameworks:

```bash
# Inspect agent configuration options
genixbit-agent inspect antigravity

# Run agent health doctor
genixbit-agent doctor

# Launch with local endpoint
export ANTIGRAVITY_API_BASE="http://127.0.0.1:11434/v1"
export OPENAI_API_KEY="genixbit-local-token"
agy
```

---

## 5. Web Preview Stack Deployment

The repository includes a ready-to-run containerized preview stack for public domains:
- `os.genixbit.com`
- `docs.os.genixbit.com`
- `packages.os.genixbit.com`

### Deployment Steps
```bash
cd deploy

# Validate configuration
docker compose config

# Start Caddy web server
docker compose up -d

# Check logs
docker compose logs -f caddy
```

---

## 6. Maintenance & Updates

### Upgrading Installed Systems
```bash
sudo apt update
sudo apt upgrade -y
```

### Rolling Back Snapshots
```bash
sudo /usr/lib/genixbit-os/rollback-snapshot.sh --snapshot 1.0.0-lts
```
