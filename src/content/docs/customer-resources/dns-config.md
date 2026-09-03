---
title: 'Pryv.io DNS zone configuration'
---


This guide describes how to declare DNS records that Pryv.io's embedded DNS server will answer for your associated domain.

> **Since v2 (2026)** DNS is served by the core binary's **embedded DNS server** (module `components/dns-server/`), not by a dedicated container. There are **two places** records can come from:
>
> - **Static entries** — declared in YAML (`dns.staticEntries` + `dns.records.root` in `override-config.yml`) and reloaded on restart. Authoritative: they shadow anything runtime.
> - **Runtime entries** — stored in PlatformDB (rqlite, cluster-wide) and picked up by the DNS server on its periodic refresh. Written by the ACME orchestrator (transient `_acme-challenge.*` TXT records) and by operators via the `bin/dns-records.js` CLI or the `POST /reg/records` / `DELETE /reg/records/:subdomain` admin endpoints.
>
> There is no longer a `service-config-leader` / admin-panel GUI — the unified config file is the source of truth for static records, and the CLI / admin API are the source of truth for runtime records.


## Table of contents <!-- omit in toc -->

1. [When do I need this?](#when-do-i-need-this)
2. [Topology prerequisites](#topology-prerequisites)
3. [Static records (YAML)](#static-records-yaml)
   1. [Static subdomains — `dns.staticEntries`](#static-subdomains--dnsstaticentries)
   2. [Root records — `dns.records.root`](#root-records--dnsrecordsroot)
   3. [Reserved subdomains](#reserved-subdomains)
4. [Runtime records (PlatformDB)](#runtime-records-platformdb)
   1. [`bin/dns-records.js` CLI](#bindns-recordsjs-cli)
   2. [Admin HTTP endpoints](#admin-http-endpoints)
5. [Record type reference](#record-type-reference)
   1. [A / AAAA](#a--aaaa)
   2. [CNAME](#cname)
   3. [TXT](#txt)
   4. [SPF](#spf)
   5. [MX](#mx)
   6. [NS / CAA / SOA](#ns--caa--soa)
6. [v1 procedure (legacy)](#v1-procedure-legacy)


## When do I need this?

This page is for operators whose Pryv.io deployment runs in **DNS-active** mode — i.e. the embedded DNS server answers for the domain (`dns.active: true`). It is **not** needed if your deployment runs in **DNSless** mode (`dnsLess.isActive: true`) or if you delegate DNS to a third party (Route 53, Cloudflare, Gandi, Infomaniak…).

Typical reasons to add records:

- Publish operator-owned subdomains (`sw.${DOMAIN}`, `mail.${DOMAIN}`, `my-service.${DOMAIN}`).
- Publish root-level records (`A`, `MX`, `TXT`, `CAA`, `NS`, `SOA`).
- Satisfy DNS-based validation challenges (ACME DNS-01 — in v2 the built-in ACME orchestrator handles this automatically; you only write TXT records manually if you run ACME externally).


## Topology prerequisites

Before any record is served, the core must be configured to run the embedded DNS server:

```yaml
dns:
  domain: example.com     # your primary domain — do not include a leading dot
  active: true            # start the embedded DNS server
  port: 53                # in prod, bind DNS to 53 (docker typically maps host 53/udp → container 53/udp)
  ip: '0.0.0.0'           # bind address
  defaultTTL: 300         # seconds
```

In multi-core, the DNS server on each core reads from the same PlatformDB and returns consistent answers cluster-wide.


## Static records (YAML)

### Static subdomains — `dns.staticEntries`

`dns.staticEntries` is a map from subdomain → record type(s). Each entry replaces the subdomain-level answer served by the DNS server — runtime records in PlatformDB for the same subdomain are shadowed (a drift warning is logged on startup if both exist).

```yaml
dns:
  staticEntries:
    sw:
      a: ['192.0.2.10', '192.0.2.11']           # two cores behind a round-robin
    mail:
      a: ['192.0.2.10']
    www:
      cname: 'my-site.example.com'
    txt-demo:
      txt: ['hello from pryv']
```

### Root records — `dns.records.root`

Root-level records (apex / `@`) for the zone live under `dns.records.root`:

```yaml
dns:
  records:
    root:
      a: ['192.0.2.10', '192.0.2.11']
      aaaa: []
      ns: ['ns1.example.com', 'ns2.example.com']
      mx:
        - { name: 'mail.example.com', priority: 10, ttl: 3600 }
        - { name: 'mail-fallback.example.com', priority: 50, ttl: 3600 }
      txt: ['v=spf1 include:_mailcust.example.com ?all']
      caa: ['0 issue "letsencrypt.org"']
      soa: null                                   # null = auto-generated
```

### Reserved subdomains

`reg`, `access`, and `mfa` are **reserved** by the distribution. Every core answers those routes itself, so the embedded DNS resolves them to all available cores' IPs automatically. Do not list them in `staticEntries` — any entry is ignored in favour of the auto-resolution.


## Runtime records (PlatformDB)

Runtime records live in the cluster-wide PlatformDB (rqlite) and are served by every core's DNS server. They are the right place for:

- **Transient validation records** — the built-in ACME orchestrator writes `_acme-challenge.<hostname>` TXT records here automatically during DNS-01 challenges.
- **Operator-owned dynamic entries** that you want to add or remove without restarting the core.

### `bin/dns-records.js` CLI

Run from the core's repository root. The CLI talks to PlatformDB directly and works whether `master` is running or not — the DNS server picks up changes on its next periodic refresh (30 s by default).

```bash
node bin/dns-records.js list                      # list all runtime records
node bin/dns-records.js load records.yaml         # upsert records from YAML
node bin/dns-records.js load records.yaml --dry-run
node bin/dns-records.js load records.yaml --replace  # wipe existing then load
node bin/dns-records.js delete <subdomain>        # remove a subdomain
node bin/dns-records.js export [file.yaml]        # dump current records as YAML
```

YAML shape for `load`:

```yaml
records:
  - subdomain: _acme-challenge
    records:
      txt: ['validation-token-from-acme-client']
  - subdomain: www
    records:
      a: ['192.0.2.10']
```

### Admin HTTP endpoints

Token-authenticated routes on `reg/records` (auth via `auth.adminAccessKey`):

- `POST /reg/records` — create or replace a subdomain's records (payload mirrors one entry of the YAML above).
- `DELETE /reg/records/:subdomain` — remove a subdomain.

These are the surfaces used by integrations that manage DNS programmatically (e.g. an external ACME client pushing TXT challenges).


## Record type reference

### A / AAAA

IPv4 / IPv6 host records. Lists.

```yaml
# static
dns:
  staticEntries:
    my-service:
      a: ['192.0.2.10']
      aaaa: ['2001:db8::10']
```

### CNAME

Alias. Single string.

```yaml
dns:
  staticEntries:
    www:
      cname: 'my-site.example.com'
```

### TXT

Array of strings. One entry = one TXT RR; multiple entries = multiple TXT RRs for the same name.

```yaml
dns:
  staticEntries:
    challenge:
      txt: ['hi there', 'my-dns-challenge']
```

### SPF

SPF records are just TXT records at the root — place them under `dns.records.root.txt`:

```yaml
dns:
  records:
    root:
      txt: ['v=spf1 include:_mailcust.example.com ?all']
```

### MX

Array of objects with `name`, `priority`, optional `ttl`:

```yaml
dns:
  records:
    root:
      mx:
        - { name: 'mail.example.com',          priority: 10, ttl: 10800 }
        - { name: 'mail-fallback.example.com', priority: 50, ttl: 10800 }
```

### NS / CAA / SOA

`dns.records.root.{ns, caa, soa}` — `ns` and `caa` are arrays of strings, `soa` is either `null` (auto-generated) or a string in standard SOA record format.


## v1 procedure (legacy)

Operators still running Pryv.io v1 used `service-config-leader` to edit `config-leader/conf/platform.yml` under `DNS_SETTINGS`. That mechanism **does not exist in v2** — the table below maps each v1 variable to its v2 equivalent for convenience when migrating:

| v1 `platform.yml` variable | v2 equivalent |
|---|---|
| `DNS_SETTINGS.settings.DNS_CUSTOM_ENTRIES.value.<sub>.ip` | `dns.staticEntries.<sub>.a[]` |
| `DNS_SETTINGS.settings.DNS_CUSTOM_ENTRIES.value.<sub>.alias.name` | `dns.staticEntries.<sub>.cname` |
| `DNS_SETTINGS.settings.DNS_CUSTOM_ENTRIES.value.<sub>.description` | `dns.staticEntries.<sub>.txt[]` |
| `DNS_SETTINGS.settings.DNS_ROOT_DOMAIN_A_RECORD.value` | `dns.records.root.a[]` |
| `DNS_SETTINGS.settings.DNS_ROOT_TXT_ARRAY.value` | `dns.records.root.txt[]` |
| `DNS_SETTINGS.settings.DNS_MX_RECORDS.value[]` | `dns.records.root.mx[]` |

### Older v1 (`dns.json`)

Pryv.io v1 deployments older than the `service-config-leader` switch stored DNS records as JSON in `pryv/dns/conf/dns.json` (single-node) or `reg-master/dns/conf/dns.json` and `reg-slave/dns/conf/dns.json` (cluster). All keys lived under a top-level `dns` property. v2 equivalent:

| v1 `dns.json` key | v2 equivalent |
|---|---|
| `dns.staticDataInDomain.<sub>.ip` | `dns.staticEntries.<sub>.a[]` |
| `dns.staticDataInDomain.<sub>.alias.name` | `dns.staticEntries.<sub>.cname` (string) |
| `dns.staticDataInDomain.<sub>.description` (string **or** array) | `dns.staticEntries.<sub>.txt[]` |
| `dns.domain_A` | `dns.records.root.a[]` |
| `dns.rootTXT.description[]` | `dns.records.root.txt[]` |
| `dns.mail[]` (`{name, ip, ttl, priority}`) | `dns.records.root.mx[]` (`{name, priority, ttl}`) — `ip` is no longer carried; resolve the MX target's A/AAAA via its own zone entry |

Notes when porting:

- **Lower-case keys.** The v1 server lower-cased subdomains; v2's YAML keys must already be lower-case (no implicit normalisation).
- **JSON → YAML.** v1's JSON was edit-fragile (a stray comma stopped the DNS server from booting). The v2 YAML loader is more permissive but still validated on startup; bad shape fails fast with a logged error from `components/dns-server/`.
- **SPF.** v1 documented SPF as a `rootTXT` entry, which is correct in v2 too — place the `v=spf1 …` string in `dns.records.root.txt[]`.
