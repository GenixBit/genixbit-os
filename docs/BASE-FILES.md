# GenixBit OS Base Files Specification

`genixbit-os-base-files` is the core system identity package for **GenixBit OS**. It provides the fundamental distribution identification files required by desktop environments, system tools, scripts, and administrative applications.

## Managed Identity Files

| File | Purpose | Values / Content |
| --- | --- | --- |
| `/etc/os-release` | Standard system identification | `NAME="GenixBit OS"`, `ID=genixbitos`, `VERSION="0.1.0-alpha"`, `UBUNTU_CODENAME=resolute` |
| `/etc/lsb-release` | LSB system identification | `DISTRIB_ID=GenixBitOS`, `DISTRIB_RELEASE=0.1.0-alpha`, `DISTRIB_CODENAME=resolute` |
| `/etc/issue` | TTY login prompt banner | `GenixBit OS 0.1.0-alpha \n \l` |
| `/etc/issue.net` | Remote/SSH login banner | `GenixBit OS 0.1.0-alpha` |

## Official System Links

* **Homepage:** `https://os.genixbit.com/`
* **Documentation & Support:** `https://docs.os.genixbit.com/`
* **Bug Reports:** `https://github.com/GenixBit/genixbit-os/issues`
* **Privacy Policy:** `https://os.genixbit.com/privacy`

## Chroot & Build Pipeline Integration

The package files defined under `packages/genixbit-os-base-files/` are applied during chroot image creation to replace baseline Ubuntu base-files entries while preserving legal attribution.
