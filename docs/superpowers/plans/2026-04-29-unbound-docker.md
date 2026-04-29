# Unbound Docker Image Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a minimal, self-maintaining Docker image running Unbound as a DNSSEC-validating recursive resolver on port 5335, published to `rccampbell/unbound` on Docker Hub via monthly GitHub Actions builds.

**Architecture:** Alpine 3.21 base with Unbound installed via apk; root hints and DNSSEC trust anchor fetched and baked in at `docker build` time; container runs `unbound -d` directly with no init system or entrypoint script. A GitHub Actions workflow builds and pushes a multi-platform image (`linux/amd64`, `linux/arm64`) on push to main and on the first of each month.

**Tech Stack:** Docker (Alpine 3.21, Unbound), GitHub Actions (`docker/build-push-action@v6`), Docker Hub

---

## File Map

| Path | Action | Responsibility |
|---|---|---|
| `unbound.conf` | Create | All Unbound resolver settings |
| `Dockerfile` | Create | Image build: install, fetch root hints + DNSSEC anchor, copy config, expose 5335 |
| `.github/workflows/build.yml` | Create | CI/CD: build and push multi-platform image on push and schedule |
| `README.md` | Create | Unraid setup, Pi-hole config, verification commands, update notes |

---

### Task 1: Write unbound.conf

**Files:**
- Create: `unbound.conf`

- [ ] **Step 1: Write the config**

Create `unbound.conf` at the project root:

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

- [ ] **Step 2: Commit**

```bash
git add unbound.conf
git commit -m "Add unbound.conf"
```

---

### Task 2: Write Dockerfile

**Files:**
- Create: `Dockerfile`

- [ ] **Step 1: Define the expected test output before writing anything**

When the image is working, this command:
```bash
docker run --rm -p 5335:5335/udp -p 5335:5335/tcp rccampbell/unbound:test &
sleep 2
dig google.com @127.0.0.1 -p 5335 +short
```
Should print one or more IP addresses (e.g. `142.250.80.46`).

And this:
```bash
dig google.com @127.0.0.1 -p 5335 +dnssec | grep -E "^;; flags"
```
Should contain the `ad` flag, confirming DNSSEC validation.

- [ ] **Step 2: Write the Dockerfile**

Create `Dockerfile` at the project root:

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

Note: `unbound-anchor` exits 1 when it successfully bootstraps a new key and exits 0 when the key was already up to date. `; exit 0` prevents the build from failing on the expected non-zero exit during initial bootstrap.

- [ ] **Step 3: Build the image**

```bash
docker build -t rccampbell/unbound:test .
```

Expected: build completes successfully. You will see output like:
```
 => [3/4] RUN wget -O /etc/unbound/named.root https://www.internic.net/domain/named.root
 => [4/4] RUN unbound-anchor -a /etc/unbound/trusted-key.key; exit 0
```
The `unbound-anchor` step may print: `No updates needed` or similar — both are fine.

- [ ] **Step 4: Run the container and verify it responds**

```bash
docker run -d --name unbound-test -p 5335:5335/udp -p 5335:5335/tcp rccampbell/unbound:test
sleep 2
dig google.com @127.0.0.1 -p 5335 +short
```

Expected: one or more IP addresses printed (e.g. `142.250.80.46`). If nothing prints, check container logs:
```bash
docker logs unbound-test
```

- [ ] **Step 5: Verify DNSSEC is working**

```bash
dig google.com @127.0.0.1 -p 5335 +dnssec | grep "^;; flags"
```

Expected output contains `ad` flag, e.g.:
```
;; flags: qr rd ra ad; QUERY: 1, ANSWER: 7, AUTHORITY: 0, ADDITIONAL: 1
```

The `ad` (Authenticated Data) flag confirms Unbound validated the response with DNSSEC.

- [ ] **Step 6: Verify access control refuses outside subnets**

```bash
dig google.com @127.0.0.1 -p 5335 -b 10.0.0.1 2>&1 | grep -E "REFUSED|connection"
```

Expected: `status: REFUSED` (if your OS allows binding to 10.0.0.1) or the query simply fails.

- [ ] **Step 7: Clean up test container**

```bash
docker rm -f unbound-test
```

- [ ] **Step 8: Commit**

```bash
git add Dockerfile
git commit -m "Add Dockerfile"
```

---

### Task 3: Write GitHub Actions workflow

**Files:**
- Create: `.github/workflows/build.yml`

- [ ] **Step 1: Create the workflow directory**

```bash
mkdir -p .github/workflows
```

- [ ] **Step 2: Write the workflow**

Create `.github/workflows/build.yml`:

```yaml
name: Build and Push

on:
  push:
    branches: [main]
  schedule:
    - cron: '0 0 1 * *'

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: docker/setup-qemu-action@v3

      - uses: docker/setup-buildx-action@v3

      - uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}

      - uses: docker/build-push-action@v6
        with:
          context: .
          platforms: linux/amd64,linux/arm64
          push: true
          tags: |
            rccampbell/unbound:latest
            rccampbell/unbound:alpine3.21
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/build.yml
git commit -m "Add GitHub Actions build and push workflow"
```

---

### Task 4: Write README.md

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write the README**

Create `README.md` at the project root:

````markdown
# unbound-docker

A minimal Docker image running [Unbound](https://nlnetlabs.nl/projects/unbound/) as a full recursive, DNSSEC-validating DNS resolver. Intended as a local upstream for Pi-hole on Unraid, replacing third-party resolvers like Quad9 entirely. Root hints and the DNSSEC trust anchor are baked in at build time; the image is rebuilt monthly to pull the latest Alpine packages and Unbound version.

## Unraid Setup

1. In the Unraid Docker tab, click **Add Container**
2. Set the repository to `rccampbell/unbound:latest`
3. Set **Network Type** to `Host`
4. Add two ports: `5335/TCP` and `5335/UDP`
5. No volumes needed
6. Apply and start the container

## Pi-hole Configuration

1. In Pi-hole settings, go to **DNS**
2. Uncheck all upstream DNS server checkboxes (Quad9, Cloudflare, etc.)
3. Under **Custom (IPv4)**, enter `127.0.0.1#5335`
4. Uncheck **Use DNSSEC** — Unbound handles DNSSEC validation; enabling it in Pi-hole too causes double-validation errors
5. Save

## Verification

Confirm Unbound is resolving directly:
```bash
dig google.com @127.0.0.1 -p 5335
```

Confirm Pi-hole is forwarding to Unbound:
```bash
dig google.com @127.0.0.1 -p 53
```

Both commands should return a valid answer. The first query to Unbound will be slightly slower (recursive resolution from root servers); subsequent queries will be served from cache.

To confirm DNSSEC is active, look for the `ad` flag in the Unbound response:
```bash
dig google.com @127.0.0.1 -p 5335 +dnssec | grep "^;; flags"
# expected: ;; flags: qr rd ra ad; ...
```

## Automatic Updates

A GitHub Actions workflow rebuilds and pushes the image on the 1st of each month, pulling the latest Alpine 3.21 packages and Unbound version. To apply the update on Unraid, pull the new image and restart the container:

```bash
docker pull rccampbell/unbound:latest
```

Then stop and start the container in the Unraid Docker tab.
````

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "Add README"
```

---

### Task 5: Push to GitHub and verify Actions

**Files:** none (remote operations only)

- [ ] **Step 1: Create a GitHub repository**

Go to https://github.com/new and create a public repository named `unbound-docker` under the `rccampbell` account. Do not initialize with any files.

- [ ] **Step 2: Add secrets to the GitHub repository**

In the repository Settings → Secrets and variables → Actions, add:
- `DOCKERHUB_USERNAME` = `rccampbell`
- `DOCKERHUB_TOKEN` = your Docker Hub access token (generate at https://hub.docker.com/settings/security)

- [ ] **Step 3: Push to GitHub**

```bash
git remote add origin https://github.com/rccampbell/unbound-docker.git
git push -u origin main
```

- [ ] **Step 4: Verify the Actions workflow ran**

Go to https://github.com/rccampbell/unbound-docker/actions

Expected: a workflow run named "Build and Push" appears and completes successfully (green check). Both tags (`latest` and `alpine3.21`) should appear on https://hub.docker.com/r/rccampbell/unbound/tags

- [ ] **Step 5: Pull and test the published image**

```bash
docker pull rccampbell/unbound:latest
docker run -d --name unbound-final -p 5335:5335/udp -p 5335:5335/tcp rccampbell/unbound:latest
sleep 2
dig google.com @127.0.0.1 -p 5335 +short
docker rm -f unbound-final
```

Expected: one or more IP addresses printed.
