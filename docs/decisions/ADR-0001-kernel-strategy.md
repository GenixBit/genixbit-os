# ADR-0001: Kernel and Platform Layer Strategy

## Status
Accepted

## Context
GenixBit OS requires a stable, high-performance, security-hardened foundation with support for modern x86_64 and ARM64 hardware, high-end GPUs (NVIDIA, AMD ROCm, Intel Arc), NPUs, and enterprise virtualization.

We evaluated:
1. Pure Microkernel (e.g. seL4, Redox) — Excellent isolation, but limited hardware driver ecosystem and GPU/NPU throughput.
2. Hybrid Kernel — High complexity, lack of mature AI accelerator toolchains.
3. Linux Foundation with Progressive GenixBit Platform Layer — Proven enterprise driver ecosystem, robust container/namespaces isolation, full GPU/Vulkan/DRM driver support, combined with GenixBit-owned userland APIs, package managers, and AI runtimes.

## Decision
Adopt a Linux 6.x LTS kernel foundation combined with an original GenixBit Platform Layer that progressively owns:
- System APIs and SDK (`GenixKit`, `GenixUI`)
- Native sandboxed package format (`.gbx`) and package manager (`gbx`)
- AI Inference & Multi-Agent Runtimes (`genixbit-ai-proxy`, `genixbit-swarm`)
- Security & Policy Guards (`genixbit-guard`, `genixbit-sandbox`)

## Consequences
- Immediate broad hardware compatibility for workstations, servers, and virtual machines.
- Clean separation between kernel drivers and GenixBit platform frameworks.
- Long-term path to replace subsystems with native GenixBit implementations.
