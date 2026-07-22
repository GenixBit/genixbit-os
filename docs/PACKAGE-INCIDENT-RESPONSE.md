# GenixBit OS Package Security Incident Response

## Severity Classification & Response Timelines

| Level | Definition | Max SLA Response | Action Required |
| --- | --- | --- | --- |
| **CRITICAL** | Remote code execution / Private key compromise | 4 Hours | Key revocation, repository freeze, emergency package release |
| **HIGH** | Privilege escalation / Denial of service | 24 Hours | Patch build, emergency testing, accelerated stable promotion |
| **MEDIUM** | Non-exploitable vulnerability / Regression | 72 Hours | Normal patch cycle via `resolute-testing` |
| **LOW** | Minor packaging flaw / Documentation typo | 7 Days | Standard maintenance release |

## Incident Handling Workflow

1. Triage report and reproduce vulnerability in isolated sandbox container.
2. Draft security fix on private security branch.
3. Perform peer code review and compile package build manifest.
4. Stage fix in `resolute-testing`, verify fix, promote to `resolute-stable`.
5. Publish Security Advisory detailing CVE, affected package versions, and remediation.
