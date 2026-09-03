---
title: 'Pryv.io SSL Certificate'
---


This document describes how to obtain and install the SSL certificate used by a Pryv.io deployment.

> **Since v2 (2026)** the core no longer ships its own `renew-ssl-certificate` helper. You provide the certificate from a source of your choice — [Let's Encrypt](https://letsencrypt.org/) / [certbot](https://certbot.eff.org/), your internal CA, a commercial CA, or your reverse-proxy's auto-renewal (Caddy, Traefik, `nginx-proxy-manager`, …) — and point the core at the resulting files.

Prerequisite: you have [obtained a domain name](/customer-resources/pryv.io-setup/#obtain-a-domain-name) and installed the core ([INSTALL](https://github.com/pryv/open-pryv.io/blob/master/INSTALL.md)).


## Table of contents <!-- omit in toc -->

1. [Which certificate do I need?](#which-certificate-do-i-need)
2. [Choose an issuance strategy](#choose-an-issuance-strategy)
3. [Strategy A — built-in auto-renewal (recommended)](#strategy-a--built-in-auto-renewal-recommended)
4. [Strategy B — reverse proxy handles ACME](#strategy-b--reverse-proxy-handles-acme)
5. [Strategy C — manual certbot + file paths](#strategy-c--manual-certbot--file-paths)
6. [v1 procedure (legacy)](#v1-procedure-legacy)


## Which certificate do I need?

| Deployment                                 | Certificate                                                         |
| ------------------------------------------ | ------------------------------------------------------------------- |
| Single-core with `dnsLess.isActive: true`  | Plain cert for `your-domain.com` (one hostname)                     |
| Multi-core using embedded DNS              | **Wildcard** cert for `*.mc.example.com` (every user gets a subdomain) |
| Multi-core with DNSless overrides          | Per-core plain certs (one cert per `core.url`)                      |

A wildcard certificate requires the **DNS-01** ACME challenge.

> **Public-facing TLS vs cluster CA.** This page is about the **public-facing** SSL cert that clients (apps, browsers, SDKs) see when they hit `https://{username}.{domain}/`. In multi-core deployments, the `bin/bootstrap.js` CLI also creates a **separate, internal cluster CA** (`/etc/pryv/ca/`) used only for mutually-authenticated TLS on the rqlite Raft channel between cores. The two are independent: you still need a publicly-trusted cert for the API. The cluster CA is self-signed by design — it never sees the public internet — and is managed entirely by the bootstrap CLI. See [single-node to cluster — Cluster security at a glance](/customer-resources/single-node-to-cluster/#cluster-security-at-a-glance).


## Choose an issuance strategy

Three practical paths, in order of operational effort (lowest first):

| Strategy | When | Operator work |
|---|---|---|
| **A — built-in auto-renewal** | You want the simplest setup; the core can reach Let's Encrypt itself; there's no reverse proxy already handling ACME. | One-time config block, then nothing. |
| **B — reverse proxy handles ACME** | You already run Caddy / Traefik / nginx-proxy-manager / similar with built-in ACME. | Unchanged — keep doing that. |
| **C — manual certbot + file paths** | You need offline-style installs, custom CAs, or another bespoke issuance path. | Issue + copy on each renewal, or wire a certbot cron. |

Strategies A and B are mutually exclusive (you'd run two ACME clients racing for the same hostname). Strategy C works alongside either — it's what the core falls back to when `letsEncrypt.enabled: false`.


## Strategy A — built-in auto-renewal (recommended)

Opt-in via the `letsEncrypt` config block. The core runs the ACME flow itself, renews well before expiry, replicates the cert to every node in a multi-core deployment via PlatformDB, and hot-swaps the running HTTPS server's TLS context (`https.Server.setSecureContext`) so there's no restart.

Minimum config on a single-core host:

```yaml
http:
  ip: 0.0.0.0
  port: 443
  ssl:
    keyFile: var-pryv/tls/your-domain.com/privkey.pem
    certFile: var-pryv/tls/your-domain.com/fullchain.pem
dnsLess:
  isActive: true
  publicUrl: https://your-domain.com
letsEncrypt:
  enabled: true
  email: ops@your-domain.com
  atRestKey: '<base64 of 32 random bytes>'
  certRenewer: true
```

Generate the `atRestKey` once:

```bash
node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"
```

Multi-core: every core must have the **same** `atRestKey` in its override YAML; `certRenewer: true` is set on exactly **one** core — typically the cluster CA holder (the node that ran `bin/bootstrap.js new-core` for the others). The renewer does the ACME work; every other core polls PlatformDB and materialises the rotated cert to disk on its next tick. See [single-node to cluster](/customer-resources/single-node-to-cluster/) for the multi-core walkthrough.

Hostnames + challenge type are **derived from topology**:

| Topology config       | Hostnames covered     | ACME challenge |
| --------------------- | --------------------- | -------------- |
| `dnsLess.publicUrl`   | the host in that URL  | HTTP-01        |
| `core.url`            | the host in that URL  | HTTP-01        |
| `dns.domain`          | `*.{domain}` + apex   | DNS-01         |

There is intentionally no `letsEncrypt.hostnames` field — the two could drift. If none of the three are set, the core refuses to start the letsEncrypt block with a loud error; fix your topology config.

**DNS-01 with the embedded DNS server** (multi-core wildcard case) has been validated end-to-end against Let's Encrypt staging. The core publishes the `_acme-challenge` TXT record through rqlite → every core's embedded DNS server → LE's 5+ geo-distributed validators.

**Reverse-proxy reload hook** — optional. If you terminate TLS in nginx / Caddy / HAProxy instead of the core, point the core at those same cert paths and give it a script to nudge the proxy on rotation:

```yaml
letsEncrypt:
  enabled: true
  # ...
  onRotateScript: /etc/pryv/hooks/reload-nginx.sh
```

```bash
# /etc/pryv/hooks/reload-nginx.sh
#!/usr/bin/env bash
nginx -t && nginx -s reload
```

Env vars passed: `PRYV_CERT_HOSTNAME`, `PRYV_CERT_PATH`, `PRYV_CERT_KEYPATH`. Non-zero exit is logged and moved past — no retry, no rollback.

**Admin visibility** — `GET /system/admin/certs` (admin-key protected) returns hostname / issuedAt / expiresAt / daysUntilExpiry for every cert the cluster is managing.


## Strategy B — reverse proxy handles ACME

Terminate TLS in your proxy (Caddy has native ACME; Traefik / nginx-proxy-manager offer plugins) and forward plain HTTP to the core on port 3000 (API) and port 4000 (HFS). Sample nginx block: [INSTALL — Running behind nginx](https://github.com/pryv/open-pryv.io/blob/master/INSTALL.md#running--behind-nginx). Leave `letsEncrypt.enabled: false` on the core. The proxy handles everything; the core doesn't even see a certificate.


## Strategy C — manual certbot + file paths

Only needed for offline-style installs, custom CAs, or other bespoke issuance paths. Install certbot from [the project instructions](https://certbot.eff.org/instructions).

### HTTP-01 challenge (single-core, public host)

The core (or your reverse proxy) must serve `/.well-known/acme-challenge/` on port 80 during the challenge. With certbot's standalone mode:

```bash
sudo certbot certonly --standalone -d your-domain.com
# → certs land in /etc/letsencrypt/live/your-domain.com/
```

Then point `http.ssl` at `/etc/letsencrypt/live/your-domain.com/fullchain.pem` and `privkey.pem`, or copy them into the path your reverse proxy expects.

### DNS-01 challenge (required for wildcards)

```bash
sudo certbot certonly --manual --preferred-challenges dns \
    -d "*.mc.example.com" -d "mc.example.com"
```

Certbot prompts you for a `_acme-challenge.mc.example.com` TXT record. Publish it in whichever DNS system answers for that domain (your registrar's zone, the core's embedded DNS if `dns.active: true`, an external provider, …) and wait for propagation:

```bash
dig TXT _acme-challenge.mc.example.com
```

When the right value comes back, continue the certbot prompt.

For a non-interactive pipeline, certbot has DNS plugins for common providers (Route 53, Cloudflare, OVH, …) — see [certbot plugins](https://eff-certbot.readthedocs.io/en/stable/using.html#dns-plugins). An API-driven plugin is the only practical way to run fully-automated wildcard renewal.

### Renewal in Strategy C

- **certbot** auto-registers a systemd timer/cron job (`certbot renew`) that runs twice a day. Reload the core (or your reverse proxy) after each successful renewal:

  ```bash
  # /etc/letsencrypt/renewal-hooks/post/reload-pryv.sh
  #!/usr/bin/env bash
  systemctl reload nginx          # or: systemctl restart pryv-core
  ```

- With Strategy A you get the same outcome (auto-renew + reload) without running certbot at all.


## v1 procedure (legacy)

Operators still running Pryv.io v1 can use the procedure shipped with the [v1 config template](https://pryv.github.io/config-template-pryv.io/):

- From 1.7.4 onward, run `./renew-ssl-certificate`. Make sure `config-leader/ssl/conf/ssl-certificate.yml` has a valid email address (mandatory since 1.9.0).
- If the pre-check fails with *"Servers are not reachable"* (the `pryvio_ssl_certificate` container cannot reach `pryvio_dns`), flip `acme.skipDnsChecks` to `true` in the same file, or raise `acme.dnsRebootWaitMs` to give DNS containers more time to start.
- Certificate files end up in `${PRYV_CONF_ROOT}/pryv/nginx/conf/secret/` as `${DOMAIN}-bundle.crt` and `${DOMAIN}-key.pem`. Run `./ensure-permissions --ignore-redis` and reboot (`./restart-config-follower && ./restart-pryv`, or *Update* from the admin panel).

None of the paths or scripts above exist in v2 — use the v2 procedures earlier on this page instead.
