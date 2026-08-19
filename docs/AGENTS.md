# GenixBit OS — Multi-Agent Swarm Platform (GenixAgent)

## 1. Overview
GenixAgent is the autonomous multi-agent orchestration framework for GenixBit OS, enabling collaborative swarms to perform complex research, coding, and system maintenance tasks under strict sandboxing.

---

## 2. Agent Lifecycle & Capabilities
- **Identity & Role**: Every agent possesses a dedicated identifier and scoped role.
- **Permission Boundary**: Agents request capabilities (`READ_FILE`, `WRITE_FILE`, `EXECUTE_COMMAND`, `NETWORK_REQUEST`) with human-in-the-loop validation for high-risk operations.
- **Audit History**: All agent tool invocations are logged to `~/.local/share/genixbit/audit/ai_permissions.jsonl`.
- **Swarm Orchestrator (`genixbit-swarm`)**: Coordinates parallel execution, consensus verification, and task dispatch across local and remote workers.
