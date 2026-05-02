# unbound-docker

A minimal Docker image running [Unbound](https://nlnetlabs.nl/projects/unbound/) as a full recursive, DNSSEC-validating DNS resolver. Intended as a local upstream for Pi-hole on Unraid, replacing third-party resolvers like Quad9 entirely. Root hints and the DNSSEC trust anchor are baked in at build time; the image is rebuilt monthly to pull the latest Alpine packages and Unbound version.

## Unraid Setup

1. In the Unraid Docker tab, click **Add Container**
2. Set the repository to `rccampbell/unbound:latest`
3. Set **Network Type** to `Host` — port 5335 is available on the host automatically; no port mapping needed
4. No volumes needed
5. Apply and start the container

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

To confirm DNSSEC is active, look for the `ad` (Authenticated Data) flag in the Unbound response. Use a DNSSEC-signed domain like `cloudflare.com` — `google.com` is not DNSSEC-signed and won't show the flag:
```bash
dig cloudflare.com @127.0.0.1 -p 5335 +dnssec | grep "^;; flags"
# expected: ;; flags: qr rd ra ad; ...
```

## Automatic Updates

A GitHub Actions workflow rebuilds and pushes the image on the 1st of each month, pulling the latest Alpine 3.21 packages and Unbound version. To apply the update on Unraid, pull the new image and restart the container:

```bash
docker pull rccampbell/unbound:latest
```

Then stop and start the container in the Unraid Docker tab.
