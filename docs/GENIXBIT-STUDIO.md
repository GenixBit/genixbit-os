# GenixBit Studio

GenixBit Studio is a planned local-first, AI-augmented coding and creation workspace designed to run natively on GenixBit OS.

> [!NOTE]
> This component is in the architectural planning stage and is not yet implemented.

## Local-First & Cloud-Optional Operation

Unlike cloud-dependent code editors, GenixBit Studio is architected around local-first execution.
- All core features, including syntax highlighting, semantic indexing, structural code search, and local AI suggestions, function completely offline.
- Developers can configure cloud endpoints (such as GitHub Copilot, OpenAI, or custom enterprise APIs) optionally, but the workspace does not require an active internet connection to serve AI features.

## The `genix` CLI Tool

The workspace will integrate with a unified command-line tool, `genix`, which allows developers to:
- Initialize new projects and workspaces from local blueprints.
- Launch the GUI or terminal-based editors directly from the CLI.
- Manage local developer agent environments, runtimes, and local repository indexing.

## Hardware-Aware Model Recommendations

To assist developers in selecting the optimal coding assistant models for their machine:
- GenixBit Studio queries the host hardware configuration (CPU cores, RAM size, system thermals, and available GPU/NPU architectures).
- It provides intelligent suggestions for local models (e.g., Qwen2.5-Coder, DeepSeek-Coder, or Gemma-3-Code) that can run efficiently within the system's memory and compute constraints.

## Agent Permissions and Sandboxing

To guarantee safety when local AI agents interact with the developer's filesystem and run code:
- AI agents run inside isolated, lightweight container environments or sandboxed processes.
- Permission prompts (similar to mobile OS permissions) are enforced when an agent requests access to:
  - Network connections (outbound API calls).
  - Write access to directories outside the active project workspace.
  - Execution of system shell commands.
- These rules prevent unverified or buggy agent code from compromising the host operating system.
