# Unbound DNS Resolver Docker Image — Design

**Date:** 2026-04-29
**Project:** unbound-docker
**Docker Hub:** rccampbell/unbound

---

## Overview

A minimal, self-maintaining Docker image running Unbound as a full recursive DNS resolver. Replaces Quad9 as Pi-hole's upstream on Unraid. Unbound performs DNSSEC-validated recursive resolution from root servers, eliminating dependency on any third-party upstream DNS provider.

Root hints and the DNSSEC trust anchor are fetched and baked in at image build time (Option A). The image is rebuilt monthly via GitHub Actions to pull the latest Alpine packages and Unbound version.

---

## Architecture

Four files, no volumes, no entrypoint scripts, no init system:

| File | Purpose |
|---|---|
| `Dockerfile` | Alpine 3.21 base; installs Unbound; fetches root hints and DNSSEC anchor at build time; copies config; exposes 5335 |
| `unbound.conf` | All resolver settings: access control, hardening, DNSSEC, cache, threads |
| `.github/workflows/build.yml` | Builds and pushes multi-platform image on push to main and monthly on the 1st |
| `README.md` | Unraid setup, Pi-hole config, dig verification, update instructions |

The container runs `unbound -d` directly — no wrapper script.

---

## Dockerfile

```dockerfile
FROM alpine:3.21
RUN apk add --no-cache unbound
RUN wget -O /etc/unbound/named.root https://www.internic.net/domain/named.root
RUN unbound-anchor -a /etc/unbound/trusted-key.key; exit 0
COPY unbound.conf /etc/unbound/unbound.conf
EXPOSE 5335/tcp
EXPOSE 5335/udp
CMD ["unbound", "-d"]
```

`unbound-anchor` exits 1 on successful bootstrap (key is new) and 0 when the key was already current. `; exit 0` prevents the build from failing on the expected non-zero exit.

---

## unbound.conf

```
server:
    verbosity: 1
    interface: 0.0.0.0
    port: 5335
    do-ip4: yes
    do-ip6: no
    do-tcp: yes
    do-udp: yes

    access-control: 127.0.0.0/8 allow
    access-control: 192.168.0.0/16 allow
    access-control: 0.0.0.0/0 refuse

    root-hints: "/etc/unbound/named.root"
    auto-trust-anchor-file: "/etc/unbound/trusted-key.key"

    hide-identity: yes
    hide-version: yes
    harden-glue: yes
    harden-dnssec-stripped: yes
    use-caps-for-id: yes

    prefetch: yes
    cache-min-ttl: 300
    cache-max-ttl: 86400
    num-threads: 2
```

IPv6 disabled. Access control allows localhost and 192.168.0.0/16 only; everything else refused.

---

## GitHub Actions Workflow

Triggers:
- Push to `main`
- Schedule: `0 0 1 * *` (first of each month, midnight UTC)

Steps: checkout → QEMU → Buildx → Docker Hub login → build and push

Platforms: `linux/amd64`, `linux/arm64`

Tags: `rccampbell/unbound:latest`, `rccampbell/unbound:alpine3.21`

Cache: GitHub Actions cache (`type=gha`)

Secrets required in the GitHub repo: `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`

---

## README Sections

1. **What it does** — full recursive resolver, no upstream dependency, DNSSEC validated, monthly auto-rebuild
2. **Unraid setup** — `rccampbell/unbound:latest`, network Host, port 5335 TCP+UDP, no volumes
3. **Pi-hole configuration** — uncheck all upstream servers, add `127.0.0.1#5335`, disable Pi-hole DNSSEC
4. **Verification** — `dig google.com @127.0.0.1 -p 5335` then `dig google.com @127.0.0.1 -p 53`
5. **Automatic updates** — pull new image and restart container on the 1st of each month

---

## Success Criteria

- `dig google.com @127.0.0.1 -p 5335` returns a valid answer with DNSSEC (`ad` flag)
- Pi-hole forwards queries through Unbound at 127.0.0.1#5335
- GitHub Actions workflow builds and pushes both tags without error
- No TCP connection resets from ISP (Comcast) since Unbound resolves from root servers, bypassing port 53 TCP to Quad9
