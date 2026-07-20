# GenixBit OS Platform Services Deployment Status

This document records the public, non-sensitive deployment status for **GenixBit OS** preview web services. Detailed cloud resource identifiers, SSH access information, key-pair names, security-group identifiers, hosted-zone identifiers, and administrator-specific paths belong in a private GenixBit operations runbook rather than the public source repository.

## Deployment Overview

| Field | Value |
| --- | --- |
| **Deployment Date** | 2026-07-20 |
| **Deployment Platform** | Dedicated AWS EC2 web instance |
| **AWS Region** | `ap-south-1` (Mumbai) |
| **Server OS** | Ubuntu 24.04.4 LTS (`noble`, `x86_64`) |
| **Initial Capacity** | `t2.small` class, 30 GB EBS |
| **Reverse Proxy and TLS** | Nginx 1.24 with Certbot and Let's Encrypt |
| **Web Container Engine** | Docker Engine 29+ and Docker Compose v2 |
| **Application Container** | `caddy:2-alpine`, bound to loopback behind Nginx |
| **Public Service Status** | **PUBLIC PREVIEW ACTIVE** according to the recorded deployment validation |

## Public Services

| Domain | Service | Recorded Status | Scope |
| --- | --- | :---: | --- |
| `https://os.genixbit.com` | Product website | **ACTIVE** | Original GenixBit OS product preview |
| `https://docs.os.genixbit.com` | Platform documentation | **ACTIVE** | Documentation landing and project guides |
| `https://packages.os.genixbit.com` | Package service status | **ACTIVE** | Static status page only; no APT repository is active |

> [!IMPORTANT]
> `packages.os.genixbit.com` must remain a status-only page until GenixBit package signing, snapshots, promotion channels, rollback, backup, key revocation, and replacement-package validation are complete. It must not expose private signing material or unverified APT configuration.

## Container Security and Isolation

The recorded deployment uses a Caddy container behind the host Nginx reverse proxy.

- Root filesystem mounted read-only.
- `no-new-privileges` enabled.
- Temporary writable paths provided through `tmpfs`.
- Website content mounted read-only.
- Docker socket not mounted into the application container.
- Application service bound to loopback rather than directly exposed as an unrestricted container port.

## HTTPS and Security Headers

The recorded deployment validation includes:

```http
Strict-Transport-Security: max-age=31536000; includeSubDomains
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
Referrer-Policy: strict-origin-when-cross-origin
Permissions-Policy: camera=(), microphone=(), geolocation=()
Content-Security-Policy: default-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; script-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'
```

Additional recorded controls:

- HTTP redirects to HTTPS.
- Let's Encrypt certificates are installed.
- Certificate renewal is managed through the host Certbot timer.
- Server administration and cloud resource details are retained privately.

## Public Verification Commands

These commands verify only public DNS and HTTPS behavior and do not require administrator credentials:

```bash
dig +short os.genixbit.com A
dig +short docs.os.genixbit.com A
dig +short packages.os.genixbit.com A

curl --fail --silent --show-error --location --head https://os.genixbit.com
curl --fail --silent --show-error --location --head https://docs.os.genixbit.com
curl --fail --silent --show-error --location --head https://packages.os.genixbit.com
```

Public verification should be automated from more than one region because DNS propagation, certificate routing, and availability can differ by resolver and location.

## Private Operations Runbook Requirements

The private GenixBit infrastructure runbook should contain:

- cloud account and resource identifiers;
- server address and SSH user;
- approved SSH key or session-manager access procedure;
- security-group and firewall rules;
- DNS hosted-zone and record-management details;
- backup and restore procedure;
- monitoring and alerting destinations;
- container restart and rollback commands;
- certificate recovery procedure;
- administrator access review;
- incident response contacts.

None of those private access details should be committed to this public repository.

## Infrastructure Follow-Up

Before treating the preview as production-grade, verify and document privately:

- [ ] A stable public endpoint such as an Elastic IP or approved load-balancing layer is attached.
- [ ] SSH access is restricted to approved administrator addresses or AWS Systems Manager Session Manager.
- [ ] Port 22 is not open to the entire internet.
- [ ] Automated operating-system security updates are configured and monitored.
- [ ] Uptime checks cover all three domains from multiple regions.
- [ ] TLS-expiry monitoring is active.
- [ ] EBS snapshot or equivalent backup policy is active.
- [ ] Container and host logs have retention and rotation policies.
- [ ] Cloud billing and resource-usage alerts are configured.
- [ ] The server has a documented replacement and DNS rollback procedure.

## Final Assessment

- **Dedicated Web Host Provisioning**: `PASS` according to the merged deployment record.
- **Product Website Deployment**: `PASS` according to the merged deployment record.
- **Documentation Deployment**: `PASS` according to the merged deployment record.
- **Package Status Page Deployment**: `PASS`; APT infrastructure remains inactive.
- **TLS and Security Headers**: `PASS` according to the merged deployment record.
- **Public Repository Metadata Hygiene**: operational identifiers and access-path details are intentionally excluded.
- **Production Infrastructure Hardening**: follow-up verification required through the private operations runbook.
