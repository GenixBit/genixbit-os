# GenixBit OS Web Preview Deployment

This directory provides a small containerized preview stack for:

- `os.genixbit.com`
- `docs.os.genixbit.com`
- `packages.os.genixbit.com`

It serves original GenixBit preview content from [`website/`](../website/) through Caddy.

## Scope

This stack is suitable for an early static preview. It does **not** provide:

- an OS build server;
- ISO downloads;
- a signed APT repository;
- private signing-key storage;
- application publishing;
- user accounts;
- model hosting;
- payment processing.

The package domain serves a status page only until secure repository publication is implemented.

## Server Requirements

- public Ubuntu or Debian server;
- amd64 architecture recommended;
- Docker Engine;
- Docker Compose plugin;
- ports 80 and 443 reachable from the internet;
- DNS control for the three domains;
- SSH key authentication;
- non-root deployment user with limited sudo access.

## DNS

Create these records using the actual public IP of the new server:

```text
os.genixbit.com             A      <NEW_SERVER_IPV4>
docs.os.genixbit.com        A      <NEW_SERVER_IPV4>
packages.os.genixbit.com    A      <NEW_SERVER_IPV4>
```

Wait for DNS to resolve before expecting automatic TLS certificate issuance.

## Install Docker

Follow Docker’s official installation documentation for the selected server distribution. Do not copy unreviewed installation scripts into production.

## Deploy

```bash
git clone https://github.com/GenixBit/genixbit-os.git
cd genixbit-os/deploy

docker compose config
docker compose up -d

docker compose ps
docker compose logs --tail=200 caddy
```

## Local Preview Without Public DNS

Use temporary localhost domain values and add them to the local hosts file:

```bash
OS_DOMAIN=os.genixbit.local \
DOCS_DOMAIN=docs.os.genixbit.local \
PACKAGES_DOMAIN=packages.os.genixbit.local \
docker compose up -d
```

Example local hosts entries:

```text
127.0.0.1 os.genixbit.local
127.0.0.1 docs.os.genixbit.local
127.0.0.1 packages.os.genixbit.local
```

For local-only testing, browser certificate warnings may occur because public certificate authorities do not issue normal certificates for `.local` names.

## Update Content

```bash
cd genixbit-os
git pull origin main
cd deploy
docker compose up -d
```

The static content is mounted read-only and updates after the repository files change.

## Firewall

Only expose required ports. A typical initial policy allows:

- SSH from trusted administrator addresses;
- HTTP 80 for certificate validation and redirects;
- HTTPS 443 TCP/UDP for public websites;
- all other inbound ports denied unless explicitly required.

Do not expose Docker’s remote API to the public internet.

## Production Checklist

- [ ] server IP and ownership recorded internally;
- [ ] DNS A/AAAA records verified;
- [ ] SSH password authentication disabled where appropriate;
- [ ] root SSH login disabled;
- [ ] firewall enabled;
- [ ] operating-system updates applied;
- [ ] Docker installed from an approved source;
- [ ] Caddy containers running without extra privileges;
- [ ] TLS certificates issued successfully;
- [ ] backups configured;
- [ ] uptime and certificate monitoring configured;
- [ ] deployment access limited to GenixBit team members;
- [ ] no production secrets stored in Git;
- [ ] package domain remains a status page until signed repository review passes.

## Stop or Remove

```bash
docker compose down
```

To remove persistent Caddy certificate/configuration volumes as well:

```bash
docker compose down --volumes
```

Removing volumes forces certificate and configuration state to be recreated.
