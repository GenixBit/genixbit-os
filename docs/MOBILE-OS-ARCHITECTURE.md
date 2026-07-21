# GenixBit Mobile OS Architecture

GenixBit Mobile OS is a planned separate operating system designed for mobile form factors, incorporating AI runtimes and cellular communication interfaces.

> [!IMPORTANT]
> The mobile OS is in the architectural planning stage and is NOT implemented in the desktop repository. It will exist in a separate repository.

## Reference-Device-First Strategy

To guarantee stability, safety, and rapid iterations:
- The initial target will focus on a designated reference device architecture (e.g. PinePhone Pro or specific open hardware platforms).
- Emulation, hardware drivers, and peripheral interfaces will be validated on this reference device before scaling to other hardware platforms.

## Battery, Thermal, and AI Scheduling

Mobile devices operate under strict power and thermal constraints:
- **AI Scheduling:** Local model executions are scheduled dynamically based on battery level and thermals. High-power model inference is deferred or throttled if battery drops below a certain threshold or if thermal limits are reached.
- **Thermal Mitigation:** A dedicated scheduling daemon monitors CPU/GPU temperature sensors and limits model concurrent requests to prevent thermal throttling.

## Signed A/B Mobile Updates

To guarantee updates do not brick the mobile device:
- The OS layout uses redundant bootable partitions (A and B).
- All system updates are securely cryptographically signed.
- Updates are written to the inactive partition in the background and verified upon reboot.
- If a boot failure is detected on the updated partition, the bootloader automatically rolls back to the previous stable partition.
