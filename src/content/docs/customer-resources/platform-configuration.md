---
title: 'Platform configuration'
description: "Which Pryv.io settings live in each core's files and which can be held once for the whole platform in the platform store: the override rule, the keys, the API and bin/platform-config.js, how a change spreads, and lockdown with its ready-made profiles."
---


A Pryv.io core reads its configuration from its files and environment (`config/default-config.yml`, the override file, a host or bootstrap file, `pryv_*` environment variables). From the release after open-pryv.io 2.0.0-rc.91, a few **platform-wide** settings can also be held once, for every core, in the **platform store**, and edited through the API (and so the administration portal) or from a core's shell. Each core can **lock down** what the API may change on it.

To see what a core actually runs with, and where each value comes from, read its [effective configuration](/reference-system/#get-the-effective-configuration).

## What lives where

| Where | What | Changed by |
|---|---|---|
| each core's files and environment | everything, as before; a key with no value in the platform store reads them exactly as before | editing the files, then a restart |
| the platform store (replicated to every core) | the keys listed [below](#keys-the-platform-store-holds), once a value is written there | `/system/admin/platform-config`, `bin/platform-config.js` |
| each core's own file, never in the store | per-core settings and the settings that govern administration itself: `admin.lockdown`, `admin.localPolicy`, `auth.adminAccessKeyScope`, secrets, topology (`dnsLess`, `portal.site`, `portal.url`), hosted sites, data stores | editing the files, then a restart |

**An upgrade writes nothing to the store and changes no value.** A key moves to the store only by an explicit write, and goes back to the files when its row is deleted.

## The override rule

A key with a value in the platform store reads that value **on every core**: it replaces the value of the files and the environment of each core (including an environment variable). Deleting the value gives each core its local value back. A core whose local value is hidden by a store value logs `[platform-config-override]` at start, and the list route shows it as `localOverride`.

A store value is checked against the key's schema when it is written; a row that does not match the schema (written by hand, or by a newer release) is ignored, and that core keeps its local value.

**The local values stay required.** A core checks `service.name`, `service.home`, `service.support`, `service.terms` and `service.eventTypes` at boot, before it reads the platform store. Keep them in the configuration file (or in the service information URL) even when the store holds them.

## Keys the platform store holds

In this release, the service information shown in `/service/info`:

| Key | Value | Applies | Write needs |
|---|---|---|---|
| `service.name` | 1 to 100 characters, no control character | at once | `config:write` |
| `service.home` | http or https URL | at once | `config:write` |
| `service.support` | http or https URL | at once | `config:write` |
| `service.terms` | http or https URL | at once | `config:write` |
| `service.eventTypes` | https URL | `/service/info` at once, event validation at each core's next start | `config:write`, step-up for a session |
| `service.assets.definitions` | https URL | at once | `config:write`, step-up for a session |

The URLs carry no credentials, quotes, angle brackets, backslashes or spaces, and are at most 2048 characters. `service.assets.definitions` (what every app's sign-in button and the auth pages load) and `service.eventTypes` (the catalogue every core validates events with) reach the whole platform: https only, and a write by an administrator session needs a recent second factor ([step-up](/customer-resources/administrators/#administrator-sessions)). The admin key and the shell tool write them without one.

**`service.eventTypes`:** if the catalogue cannot be loaded from the store's URL at a core's start (or the URL points to a private, loopback or link-local host), that core uses its own local value and logs `[platform-config-fallback]`.

**Deployments with `serviceInfoUrl`:** when the service information it serves holds `assets.definitions`, that value is now the one served (before, the built-in default `https://pryv.github.io/assets-pryv.me/index.json` hid it). Check that the URL it gives answers before upgrading.

## Editing over HTTP

| Route | Permission |
|---|---|
| [`GET /system/admin/platform-config`](/reference-admin/#list-the-platform-configuration) | `config:read` |
| [`GET /system/admin/platform-config/{key}`](/reference-admin/#get-a-platform-configuration-key) | `config:read` |
| [`PUT /system/admin/platform-config/{key}`](/reference-admin/#set-a-platform-configuration-key) `{ "value": ... }` | `config:write` |
| [`DELETE /system/admin/platform-config/{key}`](/reference-admin/#delete-a-platform-configuration-key) | `config:write` |

`config:write` is a platform-wide write: only a grant at scope `platform` gives it (roles `owner` and `operator`). The admin key in scope `full` works too (these routes are not break-glass). A value the schema refuses answers 400 with the errors; a key the store cannot hold answers 404.

For each key, the list answers the stored value (if any) with when and by whom it was written, where the value comes from (`source`: `platform-db` or `local`), `effective` (what this core reads), `localOverride` (the local value a store value hides on this core), `appliesAt` (`live` or `restart`), `stepUp`, `capability` and `locked` (this core's [lockdown](#lockdown) refuses its writes). It also answers the store's revision `rev` and `coresBehind`.

Every write and deletion is recorded in the [platform trail](/customer-resources/admin-audit/) of the core that served it, with the key and the values before and after. The reads are not recorded.

## Editing from a core's shell: `bin/platform-config.js`

Talks to the platform store directly, so it works while the API is down:

```
node bin/platform-config.js list
node bin/platform-config.js get <key>
node bin/platform-config.js set <key> <value>
node bin/platform-config.js unset <key>
node bin/platform-config.js seed [--keys a,b]
node bin/platform-config.js export
node bin/platform-config.js import <file>
```

`set` takes JSON or a plain string. `unset` deletes the row: each core reads its files again. `seed` copies this core's current local values into the store for the keys that have no row yet (skipping keys without a local value or whose value the schema refuses). `export` prints the rows as JSON; `import` sets every key of an export's `entries` (or of a `{ key: value }` file), and reports the keys this release does not know without importing them. Each write (`set`, `unset`, `seed`, `import`) leaves one line in the tool's log with the operating-system user and the core id; it is not recorded in the platform trail. The stored row says who wrote it (`updatedBy.kind: cli`). `--config <file>` layers a host configuration file, as for `bin/master.js`.

Shell access to a core is the operator's proof: the tool does not ask for a second factor and is not bound by the core's lockdown.

## How a change spreads

The process that writes reloads at once and tells the other workers of its core. Every other process checks the store's revision every `platform.configPollSeconds` (default 15, from 1 to 3600) and reloads when it moved. A key that `appliesAt: restart` (`service.eventTypes`) is read again at the core's next start.

`coresBehind` in the list answer names the cores whose processes have not loaded the latest revision yet, by the last process of each core that reported: it says which cores to wait for or restart, not that every process of a core has reloaded.

## Lockdown

When administration is managed outside the API (a PaaS, GitOps, a front proxy that owns TLS and DNS), `admin.lockdown`, in a core's own configuration file, marks what the API may not change **on that core**:

```yaml
admin:
  lockdown:
    capabilities:
      dns: readonly
      certs: hidden
    platformConfig:
      readonly: [service.name]
```

- **`capabilities.<capability>`**: `editable` (the default), `readonly` or `hidden`. The writes of a `readonly` or `hidden` capability answer `403 admin-lockdown-capability`; their reads still work. `hidden` also leaves the capability out of the portal context, so the portal does not show the module.
- **`platformConfig.readonly`**: writing or deleting one of these platform configuration keys answers `403 admin-lockdown-key`. A key whose own capability is locked is refused too.

The capability names: `setup`, `roles`, `claimCodes`, `users`, `invitations`, `cores`, `config`, `configEffective`, `certs`, `dns`, `mail`, `observability`, `migrations`, `integrity`, `audit`, `erasures`, `extId`, `autoDeletion`, `delegation`, `oauthClients`, `publishers`, `bootstrap`. A capability is named like the first part of the [permissions](/customer-resources/admin-roles/#permissions) that act on it.

**What it binds.** Every caller: administrator sessions, the setup session and the admin key, on the `/system` routes and on the admin-key writes outside them (`/reg/records` is `dns`, `/reg/admin/servers/{src}/rename/{dst}` is `cores`, `/reg/admin/invitations/post` is `invitations`, an account deletion with the admin key is `users`). It never locks reads, the session routes, setup, role management nor claim codes: naming `setup`, `roles` or `claimCodes` with another state than `editable` is a boot problem, so that a copied profile cannot lock an operator out of removing an administrator. Restrict those with [`auth.adminAccessKeyScope`](/customer-resources/administrators/#the-admin-key-authadminaccesskeyscope) and roles.

**Per core.** Lockdown is read from each core's own file, never from the platform store, and no route changes it. The platform configuration is platform-wide while lockdown is per core: a core without the block still writes the platform configuration keys for every core. Put the same block on every core when the intent is platform-wide. A core whose lockdown differs from another registered core's logs `[admin-lockdown-drift]` at start.

**Checks.** An unknown capability or key, or a lock on setup, roles or claim codes, stops the boot and is reported by `bin/check-config.js`. A `platformConfig.readonly` written for a newer release (a key this release does not know) stops an older core: remove it before rolling back. Without the block, everything stays editable, as before.

### Profiles

Ready to copy from `config/lockdown-profiles/` of the release into a core's `override-config.yml`, then restart the core:

| Profile | Assumes | Locks |
|---|---|---|
| `dokku` | a PaaS terminates TLS and renews certificates, DNS is managed by the PaaS and the DNS provider, a single core deployed from an image | `certs`, `dns`, `bootstrap` hidden |
| `gitops` | every core's files come from a repository and a pipeline, which also adds cores; platform-wide settings keep coming from the files | `bootstrap` hidden; every key the platform store can hold read-only |
| `behind-cloudflare` | a front proxy or CDN terminates TLS with its own certificates and the DNS zone is at its provider | `certs`, `dns` hidden |
| `air-gap` | no outbound connection, cores installed from the operator's own media | `observability`, `bootstrap` hidden |

Lockdown hides and refuses through the API only: it does not switch a core's own DNS server or certificate renewal off. Set `dns.active` and `letsEncrypt.enabled` to `false` for that.
