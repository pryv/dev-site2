---
title: 'Pryv.io platform setup guide'
description: A step-by-step guide for IT operators to set up a Pryv.io platform from scratch, from provisioning and domains to certificates, install and customization.
slug: customer-resources/pryv.io-setup
---


This guide, addressed to IT operators, walks through the steps to set up a Pryv.io platform from scratch.

> **Since v2 (2026)** Pryv.io is a single binary / single Docker image — `pryvio/open-pryv.io`. The authoritative install document is [INSTALL](https://github.com/pryv/open-pryv.io/blob/master/INSTALL.md) in the repository: it covers prerequisites, config skeleton, data directories, running standalone with built-in HTTPS, and running behind nginx. The guide below is the higher-level platform perspective — procurement, domain, certificate, validation, customization — and links out to INSTALL for the install-time specifics.

## Provision the machine(s)

Decide whether you need a **single-core** install (most deployments) or a **multi-core** install (scale-out or geographical compliance). The [infrastructure procurement guide](/customer-resources/infrastructure-procurement/) covers sizing tables, OS/Docker requirements and the network ports to open.


## Obtain a domain name

Register a domain with a provider that lets you edit A records (and, for multi-core, NS records). The DNS setup differs depending on the topology.

### Single-core (`dnsLess`)

The core sits on a single public URL (e.g. `https://api.example.com`) and does not run its own DNS. You only need:

```
api.example.com   3600  IN  A  <core-ip>
```

Set the matching `dnsLess.publicUrl: https://api.example.com` in your override YAML.

### Multi-core with embedded DNS

Every core runs a small DNS server that resolves `{username}.{domain}` to the user's home core. At the registrar, delegate the Pryv.io subdomain's NS records to the cores:

```
# at your top-domain registrar:
dns1.mc.example.com  3600  IN  A   <core-a-ip>
dns2.mc.example.com  3600  IN  A   <core-b-ip>
mc                   3600  IN  NS  dns1.mc.example.com.
mc                   3600  IN  NS  dns2.mc.example.com.
```

You do **not** publish `lsc.mc.example.com` or per-core (`{core-id}.mc.example.com`) records by hand — the `bin/bootstrap.js` CLI on the existing core writes them into PlatformDB and the embedded DNS server serves them. See [single-node to cluster](/customer-resources/single-node-to-cluster/) for the procedure.

If you have a single machine in this mode, use the same IP for both `dns1` and `dns2` entries.

### Multi-core with externally-managed DNS

Use this when DNS is managed by an external provider (Cloudflare, Route 53, an internal DNS server, a load balancer) rather than the core. Set an explicit `core.url` per core in the override YAML — see [INSTALL — DNSless multi-core](https://github.com/pryv/open-pryv.io/blob/master/SINGLE-TO-MULTIPLE.md#dnsless-multi-core-externally-managed-dns) — and still publish the `lsc.{domain}` A record(s) so rqlite peers can discover each other.


## Install and configure the core

See [INSTALL](https://github.com/pryv/open-pryv.io/blob/master/INSTALL.md). The short story:

1. **Choose a base storage engine.** PostgreSQL 14+ (recommended) or MongoDB 4.2+. The Docker image bundles `rqlited` (platform DB) and SQLite (audit + per-user account/index), but **not** PostgreSQL/MongoDB — those are external dependencies. For Docker installs, run the database as a sidecar container on a shared network; for native installs, point the config at your existing instance.
2. `docker pull pryvio/open-pryv.io` (or clone the repo and `just setup-dev-env && just install` for a native install).
3. Write a minimal `override-config.yml` — start from the template in [INSTALL — Minimal production config](https://github.com/pryv/open-pryv.io/blob/master/INSTALL.md#minimal-production-config). **Use literal paths**, not `${ENV_VAR}` placeholders — env-var expansion in config is not supported and the core will refuse to start if it sees any unresolved `${...}` value. Required `storages.engines.*` keys: the chosen base engine block (`postgresql` or `mongodb`), plus `filesystem.{attachmentsDirPath,previewsDirPath}`, `sqlite.path`, and `rqlite.{url,raftPort,dataDir}`. All are required at boot.
4. Start `bin/master.js` (or the Docker image) with `NODE_ENV=production` and your override file.
5. **Smoke-test it:** `curl https://your-domain.com/reg/service/info` should return a JSON descriptor including your configured `name` and `serial`. If the response is correct, proceed to [validate the installation](#validate-the-installation).

For multi-core, the upgrade path from an existing single-core install is documented in [single-node to cluster](/customer-resources/single-node-to-cluster/) and upstream in [SINGLE-TO-MULTIPLE.md](https://github.com/pryv/open-pryv.io/blob/master/SINGLE-TO-MULTIPLE.md). Adding each new core is one CLI invocation on the existing core (`bin/bootstrap.js new-core ...`) followed by booting the new core in `--bootstrap` mode — the CLI handles cluster CA, mTLS material, platform-secret transfer, DNS publishing and pre-registration in PlatformDB.

**Upgrading from v1?** If you already run Pryv.io 1.x and want to move its user data into a fresh v2 install, use the [`dev-migrate-v1-v2`](https://github.com/pryv/dev-migrate-v1-v2) toolkit — it exports from a v1 MongoDB and writes a v2-compatible backup that `bin/backup.js --restore` can import. See the toolkit's README for the current source/target matrix (MongoDB v1 source → MongoDB v2 target is supported; PostgreSQL v2 target is not yet).


## Obtain an SSL certificate

What type of certificate you need depends on the topology — see the [SSL certificate guide](/customer-resources/ssl-certificate/). Briefly:

- Single-core: a plain cert for `your-domain.com`.
- Multi-core with embedded DNS: a **wildcard** cert for `*.mc.example.com`.
- Multi-core DNSless: per-core plain certs.

You can let the core terminate TLS (`http.ssl.keyFile` / `http.ssl.certFile`) or put a reverse proxy in front; INSTALL covers both.


## Validate the installation

Run the [platform validation guide](/customer-resources/platform-validation/) — a short checklist covering process status, registration round-trip, DNS resolution (multi-core), base storage reachability and HFS.


## Set up health monitoring

Wire the endpoints from the [healthchecks guide](/customer-resources/healthchecks/) into your monitoring system. In multi-core, run the checks against each core.


## Customize authentication / registration / password-reset pages

The default auth web app is [`pryv/app-web-user-account`](https://github.com/pryv/app-web-user-account) (formerly `app-web-auth3`). To customize:

1. Fork the repo and host your fork (GitHub Pages or your own server).
2. Override these keys in your config (exact YAML shape — see INSTALL / the default config):
   - `auth.trustedApps` — allow your fork's origin(s) to act as a trusted app.
   - `services.register.authUrl` — default URL used by the auth redirect flow.
   - `services.register.passwordResetUrl` — where users land when clicking a reset link.
3. If you still want to serve the auth pages under `https://${DOMAIN}/access/`, point that path in your reverse proxy at your fork (see [FAQ — customize registration pages](/faq-infra/#customize-registration-login-password-reset-pages)).

Make sure to apply the [fork change for GitHub Pages](https://github.com/pryv/app-web-user-account/blob/master/README.md#fork-repository-for-github-pages).


## Set up email sending

Pryv.io can send transactional emails for account creation and password reset. v2 supports two delivery paths: **`in-process`** (recommended — runs inside the api-server worker, no extra process, templates in PlatformDB) and **`microservice`** (legacy `pryv/service-mail` for existing deployments). Pick one via `services.email.method` and configure SMTP, sender identity and templates per the [email configuration guide](/customer-resources/emails-setup/).


## Define your data model

With the platform running, design the streams/events structure your apps will use. Start with the [data modelling guide](/guides/data-modelling/).


## Customize event-type validation

The core validates event content against published type definitions. Point `service.eventTypes` (in the override YAML) at the definitions JSON:

```yaml
service:
  eventTypes: https://pryv.github.io/event-types/flat.json
```

Host your own file and set the URL here to extend or constrain the type catalog. See [Event Types](/event-types/) for the format.


## Other documents

More resources are on the [customer resources index](/customer-resources/) and the [FAQ](/faq-infra/).
