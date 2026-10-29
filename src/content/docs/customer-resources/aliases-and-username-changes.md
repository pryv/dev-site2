---
title: 'Pryv.io aliases and username changes'
description: Operator guide to access aliases (randomAlias) and username changes on Pryv.io, covering the two settings, routing on every topology, backup and restore, the limits of an alias, and the one-time repairs after upgrading.
---


This guide is for operators. It covers two account features that give an account more than one routable name:

- **Access aliases.** An access created with `randomAlias: true` gets a platform-unique name (`r-` followed by 8 characters) that replaces the username in its `apiEndpoint` and in its access-info. See [create access](/reference/#methods-accesses-accesses-create).
- **Username changes.** The holder of an account can change its username with a personal token. Every former username stays held by the account as an alias. See [change username](/reference/#methods-account-account-changeusername).

Both kinds of names (access aliases and former usernames) are held platform-wide by the account: nobody else can register them or take them with a change.

## Configuration

Both settings are per core, in your override configuration.

```yaml
auth:
  # How many times an account may change its username. 0 disables the change.
  usernameChangeLimit: 2

accesses:
  # Most aliases one account may hold: its `r-` access aliases plus its former
  # usernames. Past it, accesses.create with randomAlias answers
  # 400 invalid-operation (data.maxAliasesPerAccount).
  maxAliasesPerAccount: 1000
```

| Key | Default | Effect |
|---|---|---|
| `auth.usernameChangeLimit` | `2` | Changes allowed per account. `0` refuses every change (`400 invalid-operation`, `data: { usernameChangesUsed, usernameChangesLimit }`). Accounts read their allowance with `GET /account/username-changes`. |
| `accesses.maxAliasesPerAccount` | `1000` | Aliases an account may hold. An alias is held until its access is deleted: an **expired access keeps its alias**, so an account that mints aliased accesses in a loop reaches the cap unless it deletes the ones it no longer uses. A create without `randomAlias` is never affected. |

**Reserved custom account streams.** The server keeps two account fields of its own, `username` and `usernameChangeCount`. A custom account stream with either id (under `custom.systemStreams.account`, with or without a `:system:` prefix) would expose them as events, to an aliased access too, so such a configuration is refused at boot. See [system streams](/customer-resources/system-streams/).

## What keeps working after a username change

- **Tokens** issued before the change work under either name. Their access-info reports the current username (an aliased access reports its alias).
- **Sign-in** accepts a former username; the session opens under the current one. An access alias (`r-` + 8 characters) is never a sign-in name.
- **High-frequency series** stored before the change are moved under the new name and returned under either name.
- **Socket.IO**: sockets opened before the change are disconnected and reconnect under either name.
- **Webhooks** move to the new username. A step of the change that cannot complete (the webhooks move, the HF series move, the breach-scope index of the accesses) does not undo it: it is reported in the `warnings` array of the result, as `{ step, message }`.

A change that fails on storage part way is undone (`500 unexpected-error`, the account stays whole under its former username). A name taken by another account while the change runs is refused (`409 item-already-exists`) before anything is written.

## Routing

Aliases and former usernames route like the username:

- **DNSless core** (`dnsLess.isActive: true`): path-style, `https://<host>/<alias>/`.
- **Core answering DNS** (`dns.active: true`): `https://<alias>.<domain>/`. The embedded DNS answers every per-account name from the name to core rows of the platform database; a single core writes them for aliases and changed usernames as it does for registrations.
- **Multi-core**: an alias is held platform-wide and routes to the account's core like its username.

## Backup and restore

`bin/backup.js` lists each account's aliases (its access aliases and its former usernames) in the backup manifest (`aliases`), and the restore reserves them again, so aliased accesses and endpoints under a former username keep routing and a former username cannot be registered by someone else after a restore. An alias another account or core took in the meantime stays with its holder; the restore reports it (`Aliases: <n> restored, <m> held by another account or core (not restored)`). Backups written by earlier releases list no aliases.

The backup also exports the high-frequency series an account still has under a former username; the restore writes them under the username. See [backup](/customer-resources/backup/).

## What an alias does not do

An alias hides the username from the holder of the access: nothing the server returns to that access names the account. It does not stop a holder who already suspects which account it is from confirming the guess: the token also works under the account's other names, so a call made with it under a guessed username succeeds exactly when the guess is right. Describe aliases to your users and in your privacy documentation as pseudonymous endpoints, not as protection against an app that guesses.

## Upgrading from 2.0.0-rc.65 or earlier

**Before restarting on the new release**, check your configuration: the same release refuses to boot a configuration that sets `dns.domain` without an explicit `dnsLess.isActive` (BREAKING, configuration). Run `node bin/check-config.js <your config file>` first; see [DNS configuration](/customer-resources/dns-config/#upgrading-from-200-rc65-or-earlier-set-dnslessisactive-explicitly).

Releases up to 2.0.0-rc.65 left three gaps that new releases no longer create but do not repair by themselves. Run each repair once per core after upgrading.

### 1. Single core serving its own DNS: `bin/reconcile-user-cores.js`

On a single core with `dns.active: true`, aliases minted and usernames taken by a change before the upgrade have no name to core row, so their DNS name answers `NXDOMAIN`. One run gives them back:

```bash
node bin/reconcile-user-cores.js --dry-run   # report what it would change
node bin/reconcile-user-cores.js             # apply
```

- It reconciles this core's rows with its local users index: missing rows recreated, rows of names no account of the core holds any more deleted. Idempotent.
- Run it with the core's **API stopped**: stale rows are deleted from one snapshot of the index, so a registration in flight during the run can lose its row (if the API was running, run it again afterwards).
- An empty users index facing rows of this core is refused (exit code 3, nothing written, dry run included), since it usually means a lost index or a wrong `--config`. `--force-empty-local` overrides it; use it only once you have checked that the index and the configuration are the right ones.
- On a multi-core member, add `--config <your host config>` as for the core itself. A DNSless single core does not need this repair.

### 2. Every core: `bin/gather-former-series.js`

Accounts renamed before the upgrade kept the high-frequency points written before their change under the former username, where reads no longer find them. The tool moves them under the current username, merged:

```bash
node bin/gather-former-series.js --dry-run            # report only
node bin/gather-former-series.js                      # move
node bin/gather-former-series.js --user <username>    # one account only
```

- Run it once per core, once every API and HF worker of the core runs the new release. Idempotent: a second run finds nothing to move. An account's next username change makes the same move.
- On a clash, the point already under the current username is kept on PostgreSQL and SQLite; on InfluxDB, the moved one.
- **Cached credentials.** HF workers cache the series credentials of a name for a while. A worker that still holds those of a former name can write under it during and after the move: a point written after the move is moved by a second run (or the next username change); a point written during the move itself is lost on SQLite and InfluxDB (copied, then the source dropped; PostgreSQL moves in one statement). For a strict guarantee, run it with the HF workers stopped.

### 3. The platform integrity check may now report orphan user ids

The users index part of `GET /system/check-platform-integrity` (admin key) never reported anything before. It now reports each user id that holds rows in `events`, `streams`, `accesses`, `profile` or `webhooks` but belongs to no account of the index (`User id "<id>" in "<collection>" is unknown in the user index DB`). On an upgraded core it may list ids left behind by account deletions of earlier releases: they are historical leftovers, not a new fault. An account whose erasure stalled after its index entry was removed is reported there too until the erasure completes. On the SQLite engine the check lists the users of a collection from the index itself, so it cannot see such rows there.
