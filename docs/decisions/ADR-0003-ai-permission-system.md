# ADR-0003: Privileged AI Actor Permission & Governance Architecture

## Status
Accepted

## Context
AI models and autonomous agents operating on user workstations have unprecedented ability to read documents, call APIs, and execute system commands. Treating AI as an unconstrained script creates severe prompt-injection and data exfiltration vulnerabilities.

## Decision
Treat all AI runtimes, assistants, and agent swarms as **Privileged Actors** subject to explicit capability-based security:
- Operations requiring approval: `READ_FILE`, `WRITE_FILE`, `EXECUTE_COMMAND`, `NETWORK_REQUEST`, `SCREEN_CAPTURE`, `ACCESS_CAMERA`, `ACCESS_MICROPHONE`, `CHANGE_SETTING`.
- High-risk operations (e.g. modifying `/etc`, accessing private keys, executing network sockets) trigger interactive user confirmation.
- Comprehensive audit trail: Every AI action is recorded to an append-only JSONL log (`~/.local/share/genixbit/audit/ai_permissions.jsonl`).

## Consequences
- Prevents autonomous agents from executing destructive commands without oversight.
- Full compliance and enterprise auditability for GenixBit OS workstations.
