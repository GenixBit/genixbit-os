# GenixBit OS Platform Services Deployment Status

This document records the public deployment verification, DNS routing, Let's Encrypt TLS certificates, security header audit, and production status for **GenixBit OS** public preview web services.

---

## 1. Deployment Overview

| Field | Value |
| --- | --- |
| **Deployment Date** | 2026-07-20 |
| **Source Commit** | `6ab071b` |
| **Deployment Branch** | `infra/deploy-public-preview` |
| **Target Server** | AWS EC2 `genius.genixbit.com` (`3.233.87.187`) |
| **Server OS** | Ubuntu 24.04.4 LTS (`noble` x86_64) |
| **DNS Engine** | AWS Route53 (`genixbit.com` Hosted Zone `Z06099042DFAZB06TIXX4`) |
| **Reverse Proxy & SSL** | Nginx 1.24 + Certbot (Let's Encrypt TLS v1.2/v1.3) |
| **Web Container Engine** | Docker Engine 27+ & Docker Compose v2 (`caddy:2-alpine` on `127.0.0.1:8081`) |
| **Public Service Status** | **PUBLIC PREVIEW ACTIVE** (Verified HTTPS across all 3 domains) |

---

## 2. Public Domain & Service Verification

| Domain | Service | Status | HTTP/TLS Test | Security Headers |
| --- | --- | :---: | :---: | :---: |
| `https://os.genixbit.com` | Product Website | **ACTIVE** | `HTTP/2 200 OK` | Verified (HSTS, CSP, X-Frame, Nosniff) |
| `https://docs.os.genixbit.com` | Platform Documentation | **ACTIVE** | `HTTP/2 200 OK` | Verified (HSTS, CSP, X-Frame, Nosniff) |
| `https://packages.os.genixbit.com` | Package Repository Status | **ACTIVE** *(Status-Only; Non-APT)* | `HTTP/2 200 OK` | Verified (HSTS, CSP, X-Frame, Nosniff) |

> [!IMPORTANT]
> **Package Domain Protection**: `https://packages.os.genixbit.com` is configured strictly as a static status page informing visitors that production APT repository infrastructure is pending. It does NOT expose an active APT index, unverified source lists, or private signing keys.

---

## 3. Container Security & Isolation (`deploy/`)

- **Docker Container**: `genixbit-os-web` running `caddy:2-alpine` listening on `127.0.0.1:8081`.
- **Security Options**:
  - `read_only: true` (Root filesystem mounted read-only)
  - `security_opt: ["no-new-privileges:true"]`
  - `tmpfs: ["/tmp", "/run"]`
  - Website mounts set to read-only (`:ro`)
  - Docker socket (`/var/run/docker.sock`) is **NOT** mounted into container.

---

## 4. Reverse Proxy & Security Header Audit

Nginx proxies external HTTPS requests to the read-only Caddy container stack on `127.0.0.1:8081`. Caddy enforces the following security headers:

```http
Strict-Transport-Security: max-age=31536000; includeSubDomains
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
Referrer-Policy: strict-origin-when-cross-origin
Permissions-Policy: camera=(), microphone=(), geolocation=()
Content-Security-Policy: default-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; script-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'
```

- **HSTS**: Enforced for 1 year (`max-age=31536000`).
- **HTTP -> HTTPS Redirect**: Configured (`HTTP 301 Moved Permanently`).
- **TLS Certificate Renewal**: Certbot automated systemd timer active on `genius.genixbit.com`.

---

## 5. Deployment Verification Evidence

```bash
# DNS Verification
os.genixbit.com (via 8.8.8.8)        -> 3.233.87.187
docs.os.genixbit.com (via 8.8.8.8)   -> 3.233.87.187
packages.os.genixbit.com (via 8.8.8.8) -> 3.233.87.187

# HTTPS Curl Verification
curl -IL https://os.genixbit.com        # HTTP/2 200 OK
curl -IL https://docs.os.genixbit.com     # HTTP/2 200 OK
curl -IL https://packages.os.genixbit.com # HTTP/2 200 OK
```

---

## 6. Rollback & Maintenance Commands

```bash
# Connect to production host
ssh -i ~/.ssh/id_rsa ubuntu@genius.genixbit.com

# Restart web preview container stack
cd /home/ubuntu/genixbit-os/deploy
sudo docker compose restart

# Rollback web container
sudo docker compose down
git checkout main
sudo docker compose up -d
```

---

## 7. Final Assessment

- **Public Preview Launch**: `PASS`
- **DNS Routing**: `PASS`
- **TLS Certificates**: `PASS` (Let's Encrypt)
- **Container Isolation**: `PASS`
- **Security Headers**: `PASS`
