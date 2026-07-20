# GenixBit OS AI Model Catalog

## Purpose

The future GenixBit AI Center and GenixBit Store will provide a **curated catalog**, not an unreviewed mirror of arbitrary model files.

A catalog entry may describe a model and provide an installation adapter, but model weights should remain optional downloads from approved upstream sources unless GenixBit has explicit redistribution rights and a verified release process.

## Important Terminology

- **Open source software** describes source code distributed under an open-source license.
- **Open weights** means model parameters are available, often under model-specific terms.
- **Free to download** does not automatically mean open source, unrestricted, or suitable for commercial use.
- **Local model** means inference can run on the user's own machine after installation; it does not guarantee acceptable performance on every device.

The GenixBit catalog must show the correct label rather than calling every downloadable model “open source.”

## Initial Curated Families

### GenixBit Bharat AI / IndicLLM-Bharat-V1

- **Owner**: GenixBit Labs Private Limited
- **Repository**: `https://github.com/GenixBit/IndicLLM-Bharat-V1`
- **Current status**: architecture and development work in progress; no Bharat production checkpoint should be advertised until training, evaluation, safety review, and release validation are complete.
- **Planned use**: Indian-language development, education, experimentation, and future application integration.

### Google Gemma 3

- **Source**: `https://ai.google.dev/gemma/docs/core/model_card_3`
- **Type**: open-weight model family with Google terms of use.
- **Published variants**: compact through larger multimodal variants.
- **Candidate use**: compact local assistants, multilingual applications, image understanding, learning, and development.
- **Catalog rule**: display Google’s current terms and require acceptance where necessary.

### Alibaba Qwen3

- **Source**: `https://github.com/QwenLM/Qwen3`
- **Type**: open-weight family; official repository states its open-weight models are under Apache-2.0.
- **Candidate use**: coding, general assistants, agents, multilingual applications, and tool use.
- **Catalog rule**: verify the exact model repository and license before publishing each install entry.

### DeepSeek-R1 and Distilled Variants

- **Source**: `https://github.com/deepseek-ai/DeepSeek-R1`
- **Type**: reasoning model family with MIT-licensed repository/model terms described upstream; distilled variants may also inherit base-model terms.
- **Candidate use**: reasoning, coding, mathematics, and structured problem solving.
- **Catalog rule**: show both DeepSeek terms and the underlying Qwen or Llama terms for distilled variants.

### IBM Granite 3.3

- **Source**: `https://huggingface.co/ibm-granite`
- **Type**: compact model family with Apache-2.0 entries published by IBM.
- **Candidate use**: enterprise application development, RAG, assistants, code, and smaller local deployments.
- **Catalog rule**: pin the exact official IBM model identifier and license.

## Runtime Options

### Ollama

- Linux installation documentation: `https://docs.ollama.com/linux`
- Local API documentation: `https://docs.ollama.com/api/introduction`
- Intended role: simple local model installation, lifecycle management, and API access.

### llama.cpp

- Repository: `https://github.com/ggml-org/llama.cpp`
- Intended role: efficient GGUF inference across a broad range of CPU and GPU hardware, including an optional OpenAI-compatible server.

### vLLM

- Intended role: higher-throughput serving on suitable server and workstation hardware.
- Catalog rule: do not install by default on unsupported hardware.

### Containers

- Intended role: isolated deployment for server profiles and reproducible application stacks.
- Catalog rule: containers must use pinned images, documented ports, explicit volumes, and resource limits.

## Catalog Metadata Schema

Every model entry should contain:

```yaml
id: provider/model-id
name: Human-readable model name
provider: Upstream organization
source_url: Official model page or repository
license_id: SPDX identifier or model-specific terms label
license_url: Exact terms page
redistribution: allowed | restricted | unknown
commercial_use: allowed | restricted | review-required | unknown
runtime_adapters:
  - ollama
  - llama-cpp
minimum_ram_gb: 8
recommended_ram_gb: 16
minimum_vram_gb: 0
recommended_vram_gb: 8
download_size_gb: 0
quantization: optional description
capabilities:
  - chat
  - code
languages:
  - multilingual
checksums:
  sha256: optional verified digest
status: experimental | verified | deprecated
last_reviewed: YYYY-MM-DD
```

## Hardware-Aware Recommendations

The AI Center should classify a model as:

- **Recommended**: expected to fit comfortably with room for the operating system and applications.
- **Possible**: may run slowly or require reduced context/quantization.
- **Not recommended**: likely to exceed detected RAM, VRAM, architecture, or disk limits.
- **Unsupported**: runtime or model architecture is not supported on the current machine.

The system must never silently select the largest model.

## Installation Safety

Before downloading a model, show:

1. model name and upstream provider;
2. source URL;
3. license and usage terms;
4. model and quantization size;
5. required free disk space;
6. estimated RAM/VRAM tier;
7. network source;
8. checksum status;
9. runtime service that will be installed or started;
10. uninstall and data-removal instructions.

## Privacy Defaults

- Local runtimes should bind to loopback by default.
- Remote network access must require explicit configuration.
- API endpoints must not be exposed publicly without authentication, firewall rules, and transport security.
- Prompts and generated output should remain local unless the user enables a cloud provider.
- Provider API keys must use per-user secret storage and must not be written to repository files.

## Release Gate

A model entry may be marked **Verified for GenixBit OS** only after:

- official source and license review;
- clean installation and removal tests;
- checksum or trusted runtime-source verification;
- minimum hardware test;
- local API test;
- disk and memory observation;
- basic safety and functionality evaluation;
- documentation review;
- GenixBit maintainer approval.
