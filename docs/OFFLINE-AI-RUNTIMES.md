# Offline AI Runtimes

The GenixBit OS platform is designed around a secure local-first runtime layer, prioritizing developer privacy and offline availability.

> [!NOTE]
> These components are in the architectural planning stage and are not yet implemented.

## GenixBit AI Core

GenixBit AI Core serves as the base platform interface for executing local models on GenixBit OS. It abstracts hardware acceleration details (CUDA, ROCm, Vulkan, NPU drivers) and provides standard API surfaces for local applications, developer tools, and system-level utilities.

## The `genixbit-modeld` Daemon

To manage background model execution efficiently, the platform uses a dedicated system service daemon, `genixbit-modeld`:
- It manages model loading, background execution states, and resource allocation.
- It dynamically spins down idle models to free VRAM/system RAM when resources are requested by other heavy applications (e.g. compilers or IDEs).
- It exposes a secure local socket interface through which authorized client apps can interact.

## Local-Only & Cloud-Optional Architecture

By default, all model inference runs locally. The operating system guarantees:
- **No telemetry/leakage:** Zero code snippets, user prompts, or weights data are transmitted over the network.
- **Cloud-Optional fallback:** Users can explicitly connect remote APIs or commercial cloud servers, but the default state is entirely local and offline.

## Agent Permissions and Sandboxing

Runtimes executing local agent codes are sandboxed to enforce safe, transparent operations. System-level security policies restrict background model execution from accessing personal folders, system critical assets, or configuration files without explicit user approval.
