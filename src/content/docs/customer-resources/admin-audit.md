---
title: 'Administration audit trail'
description: "The platform trail of Pryv.io: what each core records of the administration acts, who acted and on what, how to read it (GET /system/admin/audit, bin/admin.js audit tail), what it holds by default and how it is kept."
---


Each core records the administration acts it serves in its own **platform trail**: who acted, with which grant, on what, and whether the act was done or refused. The trail is read with [`GET /system/admin/audit`](/reference-admin/#read-the-platform-trail) or, on the core's shell, with `node bin/admin.js audit tail`.

The platform trail comes with the release after open-pryv.io 2.0.0-rc.91. Before it, the administration acts (setup, sessions, claim codes, roles, from 2.0.0-rc.91) reached the audit syslog channel only.

## What it holds

The platform trail is stored in the core's audit storage (the same storage as the accounts' own trails, see [audit setup](/customer-resources/audit-setup/)), under the reserved id `platform-trail`. It holds the audit records of the calls **without an account of this core** whose method id starts with `system.`: the account, core and status methods of `/system`, setup, administrator sessions, roles and claim codes, the platform configuration, the OAuth review. Also recorded as administration acts:

- the acts of `bin/admin.js` (`admin.cli.role.granted`, `admin.cli.role.deleted`, `admin.cli.sessions.revoked`, `admin.cli.claimCode.created`, `admin.cli.setupCode.replaced`, `admin.cli.setup.finished`);
- the admin-key writes under `/reg`: `system.reg.servers.rename` (both core ids, the number of accounts and external ids moved), `system.reg.invitations.create` (how many, never a token nor its description), `system.reg.records.set` and `system.reg.records.delete` (the name and the kinds of record, not their values);
- an account erased with the admin key (`DELETE /users/{username}`, method `auth.delete`), done calls only.

Each act is recorded whether it was done or refused; a refused act keeps its subject and target. Among the reads, those of account data and of what an operator answers for are recorded: the accounts list (`system.listUsers`), an account's usage (`system.getUserInfo`) and an access (`system.getAccess`), both also written in the read account's own trail (`account.readByAdmin`) when it is on this core, the erasure ledger reads and the effective configuration. The other reads (status routes, setup status and checks, the role lists, the session read, the platform configuration, certificates, mail templates, the OAuth review reads) and the trail read itself are not recorded.

Besides the platform trail, an act of an administrator session is recorded in the administrator's own trail (`admin.act`) when that account is on this core, and a grant or a revocation in the grantee's (`admin.role.granted`, `admin.role.revoked`).

## A record

A record of the platform trail is an audit event (see the [audit logs guide](/guides/audit-logs/)) whose `content.record` says:

- **`subject`**: who acted. `{ via, userId?, sessionId?, role?, scope?, localGrant? }`, where `via` is `admin-key`, `session`, `setup` or `cli` (`osUser` for the shell tool); `userId` the administrator's account id; `sessionId` 16 characters identifying the session (never the token); `role` and `scope` the grant that gave the route's permission on this core; `localGrant: true` when it is one of this core's [local grants](/customer-resources/admin-roles/#local-policy).
- **`target`**: what the act names (an account, an access, a namespace, a core, a client...).
- **`diff`**: names and digests only. Never a request body, an address, a token or a secret value; a mail template body is recorded by its length and SHA-256. A grant, a revocation, a claim code (role, scope and lifetime, never the code), a claim and the first administrator name the account, the role and the scope.
- **`result`**, when the act has one.

**No username in clear.** An account is named by its id (when it is an account of this core) and by `usernameHash`, the keyed hash of its username under the erasure ledger's key (`accountErasure.ledger.hmacKey`, else derived from `auth.adminAccessKey`; without either key, by its id only). This holds in `target`, in `diff`, in the recorded query (the `search` of the accounts list becomes `searchHash`) and in the delegation stamp. Next to each keyed hash, `hashKeyId` names the key that made it, so records made before and after a key change are told apart. Set `accountErasure.ledger.hmacKey` explicitly to keep the hashes stable across an admin key rotation.

Whatever selected a record, the stored copy holds no error message in clear: `content.message` is dropped (it may quote the input); `content.id` says what was refused, and a refused handler route keeps its `HTTP <status>`. Syslog keeps the record as before. A public call opted in (below) keeps the caller's IP address.

## Which calls it keeps: `audit.platformTrail.filter`

```yaml
audit:
  platformTrail:
    filter:
      methods:
        include: ['admin-acts']
        exclude: []
```

The filter has the semantics of the other [audit filters](/customer-resources/audit-setup/#filtering) and applies together with `audit.storage.filter`. The default, `admin-acts`, keeps the administration acts above, without the refused setup-code tries (`system.setup.createSession` refusals). Public traffic without an account (`auth.register`, `auth.emailChallenge*`, the `oauth.*` events without a user, `sso.refused`, `mfa.recover`) stays in syslog only unless named, for example `include: ['admin-acts', 'auth.register']`, or `['all']` for every call without an account. Naming `system.setup.createSession` keeps its refusals; naming `auth.delete` keeps the deletions by the holder and the refused ones too. A refused `POST /system/admin/cores/ack` (anyone can call it) is logged, never stored. Boot and `bin/check-config.js` refuse a malformed filter and warn about names that select nothing.

## Reading it

**Over HTTP**, with `audit:read` (roles `owner` and `auditor`), or the admin key in scope `full`: [`GET /system/admin/audit`](/reference-admin/#read-the-platform-trail).

- Filters: `fromTime` and `toTime` (seconds, `toTime` inclusive), `methodId`, `subject` (an account id, `admin-key`, `setup` or `cli`), `target` (a value the act names: an account id, a username hash, a namespace...).
- Most recent first. `limit` (default 100, at most 1000), `skip` (at most 10000: read further by narrowing `toTime`). `skip` and `limit` count matching records; `hasMore` says whether more may follow.
- With a `subject` or `target` filter, at most 20 000 records are read per page. When that stops the read before the page is full, the answer carries `scanLimitReached: true` and `scannedToTime`, the time of the last record read: continue with `toTime` set to it and `skip: 0`, and drop by `id` the records already read (records sharing that time come again).
- Each core answers for its own trail: read every core (`GET /system/admin/cores` lists them).
- 503 when audit is off on that core or its audit storage does not keep the trail.

**On a core's shell**, also while the API is down: `node bin/admin.js audit tail [--method <id>] [--since 90m|12h|30d|<ISO date>] [--limit <n>]` prints the last records (20 by default, at most 1000), oldest first, one line each: time, method id, done or refused (with the error id), who (via, account id, role and scope) and the target.

**To look for the acts on one account**, give its id (an account of this core) or its username hash as `target`.

## How long it is kept

The platform trail is kept like every audit trail of the core: there is no retention setting and no pruning, in this release or for any other audit trail. It holds, by default, the administration acts only (setup, sessions, roles and claim codes, configuration changes, account administration, OAuth reviews and the admin-key writes under `/reg`): one record per act, so its size follows the administration activity of the platform, not the accounts' traffic. Opting public calls in through `audit.platformTrail.filter` makes it grow with that traffic.

The trail outlives the accounts it names: it is outside their erasure (an account appears in it by id and keyed username hash only). It is not part of an account backup, and a restore refuses `platform-trail` as an account id (in the backup or as the id an account is remapped to).

**Export it** before any clean-up of the audit storage, or to keep it elsewhere: read `GET /system/admin/audit` page by page on each core (by time windows with `fromTime` and `toTime`), or print the last records with `node bin/admin.js audit tail`. With `audit.syslog.active`, each record also reaches the audit syslog channel, where your own log retention applies.

**Upgrade note:** the administration acts, which reached syslog only, are now also stored: the audit storage grows with the administration traffic.
