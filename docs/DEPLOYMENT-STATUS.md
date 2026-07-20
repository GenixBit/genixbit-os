# GenixBit OS Platform Services Deployment Status

This document records the deployment readiness, local stack validation, security header audit, and production provisioning status for **GenixBit OS** public preview web services.

---

## 1. Deployment Overview

| Field | Value |
| --- | --- |
| **Deployment Date** | 2026-07-20 |
| **Source Commit** | `33768d2f820e6b699f28ab8d6d22d8d20c5f5adf` |
| **Deployment Branch** | `infra/deploy-public-preview` |
| **Target Server OS** | Ubuntu 26.04 LTS (`resolute`) / Ubuntu 24.04 LTS (`noble`) |
| **Target Server Architecture** | `amd64` (x86_64) |
| **Container Engine** | Docker Engine 27+ & Docker Compose v2 |
| **Reverse Proxy / TLS** | Caddy 2 (`caddy:2-alpine`) with Automatic HTTPS (ACME / Let's Encrypt) |
| **Deployment Status** | **Local Preview Validated** (Awaiting Public Server IP & DNS Provisioning) |

---

## 2. Target Domain & Service Architecture

| Domain | Service | Service Type | Deployment State |
| --- | --- | --- | --- |
| `https://os.genixbit.com` | Product Website | Static Web Preview | Ready for Deployment |
| `https://docs.os.genixbit.com` | Platform Documentation | Static Documentation Landing Page | Ready for Deployment |
| `https://packages.os.genixbit.com` | Package Infrastructure Status | Read-only Status Page (Non-APT) | Ready for Deployment |

> [!IMPORTANT]
> **Package Domain Scope**: `https://packages.os.genixbit.com` is explicitly configured as a static status page informing visitors that production APT repository infrastructure is pending. It does NOT expose an active APT index, unverified source lists, or private signing keys.

---

## 3. Container & Stack Validation (`deploy/`)

- **Docker Compose Spec**: `deploy/compose.yaml` validated with `docker compose config`.
- **Image**: `caddy:2-alpine`
- **Security Options**:
  - `read_only: true` (Root filesystem mounted read-only)
  - `security_opt: ["no-new-privileges:true"]`
  - `tmpfs: ["/tmp", "/run"]`
  - Website content volume mounts: Read-only (`:ro`)
  - Docker socket (`/var/run/docker.sock`) is **NOT** mounted.
- **Port Bindings**: `80:80`, `443:443` (TCP), `443:443` (UDP / HTTP/3 QUIC).

---

## 4. Security Headers & TLS Configuration (`deploy/Caddyfile`)

Caddy is pre-configured with industry-standard security hardening headers across all three domains:

```caddy
Strict-Transport-Security "max-age=31536000; includeSubDomains"
X-Content-Type-Options "nosniff"
X-Frame-Options "DENY"
Referrer-Policy "strict-origin-when-cross-origin"
Permissions-Policy "camera=(), microphone=(), geolocation=()"
Content-Security-Policy "default-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; script-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'"
-Server
```

- **HSTS Enabled**: 1-year duration (`max-age=31536000`).
- **Server Header Strip**: `-Server` header removes version disclosure.
- **Protocols**: HTTP/1.1, HTTP/2, HTTP/3 (QUIC) enabled.

---

## 5. Missing Production Inputs for Remote Provisioning

To complete public DNS pointing and automated Let's Encrypt TLS issuance, the following runtime configuration inputs must be provided by the GenixBit infrastructure administrator:

1. `NEW_SERVER_IPV4`: Public IPv4 address of the hardened production web server.
2. `SSH_USER`: Non-root deployment user with `sudo` access.
3. `SSH_PRIVATE_KEY_PATH` / SSH agent access: Authorized SSH key.
4. `DNS_PROVIDER_ACCESS`: Cloudflare / DNS provider credentials to configure `A` records for `os`, `docs`, and `packages` subdomains.

---

## 6. Remote Server Deployment Commands

Once `NEW_SERVER_IPV4` and SSH access are available, execute the following deployment sequence on the remote server:

```bash
# 1. Connect to remote production server
ssh ${SSH_USER}@${NEW_SERVER_IPV4}

# 2. Clone repository and checkout release branch
git clone https://github.com/GenixBit/genixbit-os.git
cd genixbit-os
git checkout infra/deploy-public-preview

# 3. Verify Docker Compose configuration
cd deploy
docker compose config

# 4. Launch web services container stack
docker compose up -d

# 5. Verify running container status and Let's Encrypt TLS logs
docker compose ps
docker compose logs --tail=200 caddy
```

---

## 7. Rollback Procedure

If service issues occur after remote deployment:

```bash
# Emergency container stop
cd deploy
docker compose down

# Rollback repository to last known stable commit
git checkout main
docker compose up -d
```

---

## 8. Final Readiness Assessment

- **Local Stack Validation**: `PASS`
- **Security Header Audit**: `PASS`
- **Content & Branding Review**: `PASS` (Original GenixBit content; download links marked unavailable; package repository marked inactive status page)
- **Public Remote TLS Deployment**: `AWAITING SERVER PROVISIONING`
