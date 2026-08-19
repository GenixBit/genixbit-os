# GenixBit OS — Driver & Hardware Abstraction Architecture (GenixHAL)

## 1. Overview
GenixHAL provides device discovery, lifecycle management, access controls, and power management across modern PC workstation and server hardware architectures.

---

## 2. Driver Categories

| Category | Subsystem Driver | Hardware Support | Acceleration |
| :--- | :--- | :--- | :--- |
| **GPU** | `nouveau` / `nvidia`, `amdgpu`, `i915` / `xe` | NVIDIA RTX, AMD Radeon, Intel Arc | DRM / KMS / Vulkan |
| **NPU / AI** | `intel_vpu`, `amd_xdna`, DirectML | Intel Core Ultra, AMD Ryzen AI | OpenVINO, ONNX Runtime |
| **Storage** | `nvme`, `ahci`, `virtio_blk` | NVMe PCIe 4.0/5.0, SATA SSD, QEMU VirtIO | Direct I/O & Trim |
| **Network** | `e1000e`, `igb`, `r8169`, `iwlwifi`, `ath11k` | 10GbE, Intel Wi-Fi 6E/7, Realtek | TCP BBR & WireGuard |
| **Audio** | `snd_hda_intel`, `snd_soc_sof` | Realtek ALC, USB Audio Class, Bluetooth LDAC | PipeWire low-latency |
| **Input** | `hid_generic`, `usbhid`, `i2c_hid` | Mechanical keyboards, high-DPI mice, trackpads | Multi-touch gestures |
| **Display** | `drm_kms_helper`, `edid` | HDMI 2.1, DisplayPort 2.1, eDP, USB-C DP Alt | HiDPI & Variable Refresh |

---

## 3. Crash Isolation & Device Security
- Drivers operate under least-privilege udev tagging.
- Kernel driver crashes are logged to systemd-journald without bringing down the compositor.
