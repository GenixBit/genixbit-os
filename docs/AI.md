# GenixBit OS — AI Runtime & Local Model Platform (GenixAI)

## 1. Local AI Architecture
GenixAI delivers private, local-first inference across modern CPU, GPU, and NPU accelerators.

```mermaid
graph TD
    Client["GenixKit Apps / Terminal / Spotlight"] --> Proxy["GenixAI Proxy (127.0.0.1:11434)"]
    Proxy --> Engine["Inference Engine (GGUF / Llama.cpp / Ollama)"]
    Engine --> Quant["Quantization Engine (Q4_K_M, Q8_0, FP16)"]
    Quant --> VRAM["GPU VRAM / System Memory Allocator"]
```

---

## 2. Supported Features
- **Local Chat & Streaming**: OpenAI & Ollama compatible REST & SSE endpoints (`/v1/chat/completions`, `/v1/models`, `/health`).
- **Embeddings & Vector Memory**: High-throughput embedding endpoint on `/v1/embeddings` for local RAG indexing.
- **Hardware Quantization Recommendation**: Dynamic inspection of GPU VRAM via `genixbit-gpu-diag` to recommend optimal quantization formats.
