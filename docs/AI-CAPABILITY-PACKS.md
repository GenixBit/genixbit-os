# AI Capability Packs

AI Capability Packs are planned packages designed to easily provision and configure local models on GenixBit OS.

> [!NOTE]
> These packages are in the planning stage and are not yet implemented.

## Offline `.gbmodel` Bundles

Model weights, configuration profiles, and system dependencies are packaged into unified `.gbmodel` bundles:
- These bundles can be downloaded, backed up, and copied offline.
- They are designed to allow full offline installation of AI features without requiring package repository connections or model downloads at setup time.
- Note that while some models in these bundles are open source, others have restrictive commercial licenses, research-only licenses, or custom open-weights terms. They are not all open source.

## Model Catalog Levels

To help developers assess the safety, integration level, and license constraints of each pack, the catalog has three levels:

1. **Verified Level:**
   - Fully tested by GenixBit Labs.
   - Guaranteed to work with host hardware acceleration.
   - Completely integrated with GenixBit Studio and system tools.
2. **Community Level:**
   - Verified by the community.
   - May require custom settings or hardware configurations.
3. **External Level:**
   - External registry URLs (e.g. Hugging Face, Ollama library).
   - Subject to third-party licenses and direct user configuration.

## Hardware-Aware Model Recommendations

When downloading or enabling model packs:
- The system automatically profiles CPU threads, system memory, and GPU/VRAM capability.
- It advises against installing heavy models (e.g., 32B or 70B parameter models) on low-spec systems, recommending optimized quantized models (e.g., Qwen-Coder-7B-Instruct or Gemma-3-8B) for fluid performance.
- The training, evaluation, and production capability of Bharat-V1 remains under active development and is not yet production ready.
