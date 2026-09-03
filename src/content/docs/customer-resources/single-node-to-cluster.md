---
title: 'Pryv.io — single-core to multi-core upgrade'
description: How to upgrade a single-core Pryv.io deployment to multi-core with a config-only change, issuing bootstrap bundles so new cores join the cluster over TLS.
---


This guide describes how to upgrade a running single-core Pryv.io deployment to a multi-core setup, where several cores share the same platform and split users among themselves.

> **Since v2 (2026)** there is **no data migration involved**. The platform DB (rqlite) is already in place on the single-core install — going multi-core is a **config-only** change plus issuing a sealed bundle for each new core. No separate register, DNS or static-web machines to provision, and no user data to copy. Users that already existed on the single core stay on that core; new registrations are distributed across all available cores.
>
> **Since v2.0.0** the procedure is driven by the `bin/bootstrap.js` CLI on the existing core: one command per new core produces a passphrase-encrypted bundle, the new core boots in `--bootstrap` mode and joins the cluster over mutually-authenticated TLS automatically. The previous edit-override-YAML-by-hand workflow is preserved as an Appendix for offline-style installs.
>
> This page is the platform-operator narrative around the upstream [SINGLE-TO-MULTIPLE.md](https://github.com/pryv/open-pryv.io/blob/master/SINGLE-TO-MULTIPLE.md), which contains the exact config snippets and verification commands.


## Table of contents <!-- omit in toc -->

1. [Prerequisites](#prerequisites)
2. [Outcome at a glance](#outcome-at-a-glance)
3. [How adding a core works](#how-adding-a-core-works)
4. [Decide on a DNS strategy](#decide-on-a-dns-strategy)
5. [Pick a wildcard SSL strategy](#pick-a-wildcard-ssl-strategy)
6. [Step 1 — Set up DNS](#step-1--set-up-dns)
7. [Step 2 — Switch the existing core to multi-core mode](#step-2--switch-the-existing-core-to-multi-core-mode)
8. [Step 3 — Issue a bootstrap bundle for the new core](#step-3--issue-a-bootstrap-bundle-for-the-new-core)
9. [Step 4 — Transfer bundle + passphrase to the new core](#step-4--transfer-bundle--passphrase-to-the-new-core)
10. [Step 5 — Boot the new core in `--bootstrap` mode](#step-5--boot-the-new-core-in---bootstrap-mode)
11. [Step 6 — Verify cross-core operation](#step-6--verify-cross-core-operation)
12. [Cluster security at a glance](#cluster-security-at-a-glance)
13. [Operations: managing in-flight bundles](#operations-managing-in-flight-bundles)
14. [Nginx / reverse-proxy notes](#nginx--reverse-proxy-notes)
15. [Rollback](#rollback)
16. [Appendix — manual bootstrap (no CLI)](#appendix--manual-bootstrap-no-cli)


## Prerequisites

- A running single-core Pryv.io v2 install with real users and data.
- DNS control for the target shared domain (you need to publish wildcard A records and an `lsc.{domain}` A record; or, in DNSless mode, NS+A records only).
- At least one more machine or Dokku app for the second core.
- A base-storage database (PostgreSQL or MongoDB) for the second core — separate from the first core's.
- The wildcard (or per-core) SSL certificate covering the new domain.
- `openssl` available on the existing core (used by the bootstrap CLI to mint the cluster CA on first run — already a system dep on any Pryv.io host).


## Outcome at a glance

|                     | Before                         | After                                                                 |
| ------------------- | ------------------------------ | --------------------------------------------------------------------- |
| Cores               | 1 (single node)                | 2+ (one existing + one or more new)                                   |
| Platform DB         | rqlite (single, embedded)      | rqlite (clustered, embedded on every core, joined via DNS discovery)  |
| Base storage        | 1 (PostgreSQL or MongoDB)      | 1 per core — cores never share the base DB                            |
| User routing        | All users on one instance      | Each core hosts a subset; discovery via `/reg/cores?username=`        |
| Public URL          | `https://api.example.com` (dnsLess) or single domain | `{username}.mc.example.com` or per-core URLs (DNSless)  |
| Raft channel        | local only (loopback)          | mutually-authenticated TLS between cores                              |
| Adding a core       | n/a                            | one CLI invocation issues a sealed bundle                             |


## How adding a core works

The existing core (call it `core-a`) keeps a self-signed **cluster CA** in `/etc/pryv/ca/` and a token store in `/var/lib/pryv/bootstrap-tokens.json`. To add a new core (`core-b`):

1. On `core-a`, run `bin/bootstrap.js new-core --id core-b --ip <ip>`. This:
   - generates the cluster CA on first run (one time only — back up `/etc/pryv/ca/`),
   - issues a node cert + key signed by the CA, scoped to `core-b`,
   - mints a one-time join token (24 h TTL by default),
   - pre-registers `core-b` in PlatformDB as `available:false` and publishes its DNS records,
   - bundles everything — identity, platform secrets, TLS material, ack URL, token — into a passphrase-encrypted file.
2. Transfer the bundle file and the passphrase to `core-b` over **separate** secure channels.
3. On `core-b`, run `bin/master.js --bootstrap <bundle> --bootstrap-passphrase-file <pass>`. This:
   - decrypts and validates the bundle,
   - writes `override-config.yml` and the TLS files to disk,
   - POSTs an ack to `core-a` (TLS pinned to the bundled CA),
   - on success, deletes the bundle file (the join token is one-shot),
   - chains into normal startup — joining the rqlite cluster over mTLS.

Once the ack lands, `core-a` flips `core-b` to `available:true` in PlatformDB. Both cores now serve the cluster.


## Decide on a DNS strategy

Two shapes of multi-core deployment are supported:

1. **Embedded DNS** — the cores answer DNS queries for `*.mc.example.com`. You publish NS records at the registrar that delegate the Pryv.io subdomain to the cores. The bootstrap CLI publishes the per-core `{core-id}.{domain}` and `lsc.{domain}` records into PlatformDB; you don't maintain them by hand.
2. **Externally-managed DNS (DNSless multi-core)** — an external DNS provider (Cloudflare, Route 53, internal DNS, load balancer) resolves core hostnames. Cores advertise explicit `core.url` values via the platform DB and the client SDK uses the discovery endpoint rather than DNS to find the right core. Use the CLI's `--url <https://…>` flag when issuing the bundle.

In both cases, an `lsc.{domain}` A record listing every core IP is needed for rqlite peer discovery.

See [SINGLE-TO-MULTIPLE.md — DNSless multi-core](https://github.com/pryv/open-pryv.io/blob/master/SINGLE-TO-MULTIPLE.md#dnsless-multi-core-externally-managed-dns) for the externally-managed variant.


## Pick a wildcard SSL strategy

- Embedded DNS: one **wildcard** cert for `*.mc.example.com` used by all cores.
- DNSless: per-core plain certs for each `core.url`.

Note: this is the **public-facing** SSL cert — separate from the **cluster CA** the bootstrap CLI creates for the Raft channel. See the [SSL certificate guide](/customer-resources/ssl-certificate/) for the distinction.


## Step 1 — Set up DNS

**Embedded DNS variant** — publish at the registrar:

```
dns1.mc.example.com  3600  IN  A   <core-a-ip>
dns2.mc.example.com  3600  IN  A   <core-b-ip>
mc                   3600  IN  NS  dns1.mc.example.com.
mc                   3600  IN  NS  dns2.mc.example.com.
```

You do **not** need to maintain `lsc.mc.example.com` or per-core records by hand — the bootstrap CLI publishes them into PlatformDB and the embedded DNS server serves them. (You only maintain them by hand in the manual-bootstrap appendix.)

**DNSless variant** — publish A records at your provider for each `core.url`, plus the `lsc.{domain}` record listing every core's IP.


## Step 2 — Switch the existing core to multi-core mode

The existing core is in single-core (dnsLess) mode. Edit its config to identify itself in the cluster:

```yaml
# REMOVE (single-core / dnsLess)
# dnsLess:
#   isActive: true
#   publicUrl: https://old-single-core.example.com

dnsLess:
  isActive: false

core:
  id: core-a              # this core's identifier
  ip: <host-public-ip>
  available: true

dns:
  domain: mc.example.com  # shared domain for all cores
  active: false           # set to true only if the core itself should answer DNS queries
```

Restart `bin/master.js`. The core identifies itself as `core-a` and is reachable at `https://core-a.mc.example.com/`. The embedded rqlited continues as a single-node cluster — until the first new core joins.


## Step 3 — Issue a bootstrap bundle for the new core

On `core-a` (the existing core, which holds the cluster CA):

```bash
node bin/bootstrap.js new-core \
    --id core-b \
    --ip 1.2.3.4 \
    --hosting us-east-1 \
    --out /tmp/core-b.bundle.age
```

The CLI prints something like:

```
[ca] new cluster CA generated at /etc/pryv/ca
[ca] BACK UP THIS DIRECTORY — losing it means you cannot add cores later.

Bundle written:
  file       : /tmp/core-b.bundle.age
  passphrase : AbCd-EfGh-IjKl-MnOp
  expires    : 2026-04-18T08:42:00.000Z
  ack URL    : https://core-a.mc.example.com/system/admin/cores/ack
```

> **Back up `/etc/pryv/ca/` immediately** after the first run. The CA private key never leaves this host. If you lose it, you cannot add or rotate cores without standing up a new cluster.

The CLI:
- generated the cluster CA (only on the very first invocation),
- pre-registered `core-b` in PlatformDB as `available:false`,
- appended `1.2.3.4` to the `lsc.mc.example.com` DNS record,
- added a `core-b.mc.example.com` A record,
- minted a one-time, 24 h-TTL join token.

For DNSless multi-core, add `--url https://api2.example.com` so the explicit URL is included in the bundle.


## Step 4 — Transfer bundle + passphrase to the new core

Send the bundle file and the passphrase **on different channels**:

- file via `scp` / `rsync` / managed file transfer,
- passphrase via password manager / Signal / sealed envelope.

The bundle is encrypted with AES-256-GCM keyed off the passphrase via scrypt, but the passphrase is the only thing standing between an attacker who steals the file and full cluster admin access. Don't put both in the same email.


## Step 5 — Boot the new core in `--bootstrap` mode

On `core-b` (a fresh host with a base storage already provisioned and `bin/master.js` installed):

```bash
# Write the passphrase to a file readable only by the master process
echo "AbCd-EfGh-IjKl-MnOp" > /root/core-b.pass
chmod 600 /root/core-b.pass

node bin/master.js \
    --bootstrap /root/core-b.bundle.age \
    --bootstrap-passphrase-file /root/core-b.pass
```

The master process:
- decrypts and validates the bundle,
- writes `override-config.yml` to its config directory and `/etc/pryv/tls/{ca,node}.{crt,key}` (mode 0600 for the key),
- POSTs an ack to the URL embedded in the bundle, with TLS pinned to the bundled CA,
- on success, deletes the bundle file (the token is single-use; replay attempts get a 401 from the ack endpoint),
- continues into normal startup — `rqlited` joins the cluster over mTLS.

The ack response includes a snapshot of the cluster's cores so you can sanity-check what you've joined before the master proceeds with normal startup.

### Common pitfalls when bringing up a fresh cluster on a freshly-delegated domain

Most single-to-multi-core runs on an **existing** zone with a **valid wildcard cert** are uneventful. The gotchas below tend to bite the operator once, when the cluster is being brought up on a **new** domain before DNS delegation has reached the registrar and before Let's Encrypt has issued the new wildcard:

1. **Bootstrap ack fails TLS verification.** The ack POST uses HTTPS with the cluster CA pinned. If the existing core is serving a public CA (Let's Encrypt) cert for its `dns.domain` instead of a cluster-CA-signed cert, the new core will refuse to connect. The clean way around this is to run the existing core on **plain HTTP** during the bootstrap window: set `core.url: http://<existing-core-ip>` and `http.port: 80`, remove `http.ssl`, restart, issue the bundle (its `ackUrl` is now `http://…`), run `--bootstrap` on the new core, then revert to 443/HTTPS and restart.
2. **`rqlited` can't start because `lsc.{domain}` is NXDOMAIN.** Master spawns `rqlited` with `-disco-mode dns -disco-config {"name":"lsc.<dns.domain>",...}`. On a zone that is not yet delegated at the registrar, that lookup fails and rqlite never bootstraps — the master times out after 30 s with "rqlited did not become ready". Add an `/etc/hosts` entry on each core pointing `lsc.<domain>` at the first core's IP. It can be removed as soon as the NS change has propagated and `dig lsc.<domain>` resolves publicly.
3. **`bootstrap-tokens.json` permission trap.** `bin/bootstrap.js new-core` must run as the same user that runs `bin/master.js`, **not** as root. The default token store is `/var/lib/pryv/bootstrap-tokens.json` and the default CA dir is `/etc/pryv/ca`. If you ran bootstrap with `sudo` on a first-time install, chown those paths to the master's user (`chown -R pryv: /var/lib/pryv /etc/pryv`) — otherwise the ack endpoint returns HTTP 500 with `EACCES` when it tries to consume the token. (Alternatively, override `cluster.ca.path` and `cluster.tokens.path` to locations under the master's home directory.)
4. **`pkill -f "node bin/master"` self-match over SSH.** When you run a remote kill command inside `ssh host bash -c '…'`, the remote `bash -c` cmdline contains the pattern text and pkill kills the shell itself mid-script. Use `killall <binary>` (matches on binary name only) or put the kill in a script file on the remote.


## Step 6 — Verify cross-core operation

Upstream gives the exact curl sequence — [SINGLE-TO-MULTIPLE.md — Verify cross-core operation](https://github.com/pryv/open-pryv.io/blob/master/SINGLE-TO-MULTIPLE.md#6-verify-cross-core-operation). The essentials:

```bash
# Both cores listed, both available
curl -s https://core-a.mc.example.com/system/admin/cores -H 'Authorization: <admin-key>'
# → { cores: [
#       { id: "core-a", available: true, userCount: N },
#       { id: "core-b", available: true, userCount: 0 }
#   ]}

# Register a user on core-b
curl -s https://core-b.mc.example.com/users -X POST \
  -H 'Content-Type: application/json' \
  -d '{"appId":"test","username":"newuser","password":"pass","email":"new@test.com","invitationtoken":"enjoy","languageCode":"en"}'

# Discover from core-a — should return core-b's URL
curl -s 'https://core-a.mc.example.com/reg/cores?username=newuser'
# → { core: { url: "https://core-b.mc.example.com" } }
```

Then run the [platform validation checklist](/customer-resources/platform-validation/) and the [healthchecks](/customer-resources/healthchecks/) — once against each core.


## Cluster security at a glance

- **Raft channel uses mTLS.** Bootstrap-issued cores ship with TLS material wired into `override-config.yml`. Both ends of every Raft connection verify the peer's cert against the cluster CA — a stranger on the network cannot join or impersonate a peer.
- **The cluster CA private key lives only on the issuing core**, in `/etc/pryv/ca/ca.key` (mode 0600). Only this host can issue new node certs. Back up this directory off-host.
- **Join tokens are one-shot.** A token verifies exactly once at the ack endpoint and is then burned; replays return 401. Default TTL 24 h.
- **Bundles are AES-256-GCM encrypted** with a scrypt-derived key. Tampering breaks GCM auth at decrypt time.
- **The Raft port (default 4002) does not need to be VPN-protected** between cores by default — `verifyClient: true` rejects plain TCP.

See [INSTALL.md — Cluster security](https://github.com/pryv/open-pryv.io/blob/master/INSTALL.md#cluster-security) for the full operator-level reference.


## Operations: managing in-flight bundles

```bash
# List active (un-consumed, un-expired) tokens
node bin/bootstrap.js list-tokens
# coreId           expiresAt                  issuedAt
# core-c           2026-04-18T08:42:00.000Z   2026-04-17T08:42:00.000Z

# Operator changes their mind — revoke a token AND undo the pre-registration
node bin/bootstrap.js revoke-token core-c --ip 5.6.7.8
# Revoked 1 active token(s) for core-c.
# Cleaned up DNS/PlatformDB: coreInfoDeleted=true, perCoreDeleted=true, lscIpsAfter=[1.2.3.4]
```

If `--ip` is omitted, only the token is revoked; the DNS / PlatformDB pre-registration stays. Pass `--ip <ip>` to fully unwind the issuance.


## Nginx / reverse-proxy notes

Each core still needs the same two upstreams as before — API on 3000 and HFS on 4000 — see [INSTALL — Running behind nginx](https://github.com/pryv/open-pryv.io/blob/master/INSTALL.md#running--behind-nginx). Extra items to remember in multi-core:

1. **HFS Host header** — keep `proxy_set_header Host 127.0.0.1:4000;` for the HFS locations.
2. **Socket.IO** — WebSocket-only upgrade handling for `/socket.io/`. In cluster mode the core refuses HTTP long-polling.
3. **Upload size** — `client_max_body_size` matches `uploads.maxSizeMb`.
4. **Raft port (4002)** — not through nginx; a straight TCP path between cores. With mTLS enabled, opening it on the public network is acceptable.


## Rollback

If something goes wrong, you can revert to single-core without losing data:

1. Stop the second core.
2. On the first core, run `node bin/bootstrap.js revoke-token <id> --ip <ip>` for each removed core to clean up DNS + PlatformDB.
3. Put the first core's config back to `dnsLess.isActive: true` with its previous `dnsLess.publicUrl`, and remove `core.id` / `dns.domain`.
4. Restart — the embedded rqlited runs as a standalone node again with the same platform data.

**No data migration in either direction** — rqlite is authoritative throughout and base storage was never shared, so user data stays where it already is.

If you were running on Pryv.io v1 and still need the legacy procedure, it is archived as the [v1 register migration reference](/customer-resources/register-migration/). None of the v1 steps apply to a v2 install.


## Appendix — manual bootstrap (no CLI)

The `bin/bootstrap.js` CLI is the recommended path for every multi-core install. The manual flow is preserved for two cases:

- **Offline-style installs** where the new core can never reach the existing core to ack (air-gapped tenant, maintenance window where the existing core is intentionally unavailable, etc.).
- **Operators who want full control** over each step (e.g. integrating an existing internal PKI in place of the self-signed cluster CA).

Upstream documents the five manual steps in [SINGLE-TO-MULTIPLE.md — Appendix — manual bootstrap (no CLI)](https://github.com/pryv/open-pryv.io/blob/master/SINGLE-TO-MULTIPLE.md#appendix--manual-bootstrap-no-cli):

1. Generate a cluster CA (or supply your own).
2. Issue a node cert for the new core.
3. Pre-register the new core in PlatformDB (`bin/dns-records.js` for DNS, plus the cores table).
4. Hand-write `override-config.yml` on the new core — copying platform secrets from the existing core.
5. Start the new core; `Platform.registerSelf()` writes its entry as `available:true`.

The CLI path collapses these into two operator commands and removes the race in step 3 plus the secret-copying mistake in step 4. **Use the CLI unless you specifically can't.**
