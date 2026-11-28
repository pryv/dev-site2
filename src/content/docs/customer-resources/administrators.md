---
title: 'First boot and administrators'
description: "How a new Pryv.io platform gets its first administrator (setup code, built-in setup page), how administrators sign in (administrator sessions, step-up), how more administrators get a role (claim codes), and what the admin key still does."
---


A Pryv.io platform is administered by **administrators**: accounts of the platform that hold an administrator **role**. This page covers the first boot of a new platform, how an administrator signs in to the administration API, how more administrators get a role, and what the admin key (`auth.adminAccessKey`) still does. Roles, their scopes and each core's local policy are in [Roles, scopes and local policy](/customer-resources/admin-roles/); what administrators do is recorded in the [administration audit trail](/customer-resources/admin-audit/). Every route is in the [Admin API reference](/reference-admin/).

The setup step, administrator sessions, the `owner` role, claim codes and the break-glass key scope come with open-pryv.io 2.0.0-rc.91. The other roles, the grant scopes and role management over HTTP come with the release after 2.0.0-rc.91.

## Setup state

The platform store holds a setup state: `pending` (the platform waits for its first administrator) or `ready`.

- **A fresh platform** (no account, no other core): the first core that boots writes `pending` and mints the setup code. The first writer wins, so only one core of a platform does it.
- **An existing platform upgraded** to 2.0.0-rc.91 or later (it has accounts, or other cores): its first boot writes `ready` directly. No code is printed, and admin-key calls behave as before. Its first administrator gets the role from a [claim code](#claim-codes).
- A core that joins a platform later (`bin/master.js --bootstrap`) never mints a code: it reads the state.

**While setup is pending, registration is closed** (`setup.registrationWhilePending: closed`, the default): `POST /users` answers 403, except for the first administrator's account created through the setup session. This changes the first boot of a fresh install only.

**Automated installs** (CI rigs, images, infrastructure as code) that provision with the admin key and never open the setup page finish setup without a first administrator: `node bin/admin.js setup finish` on a core, or `POST /system/setup/finish` with the admin key. Registration opens; the first administrator comes later from a claim code. Or set `setup.registrationWhilePending: open` to keep registration open meanwhile.

## The setup code

- 130 random bits, shown as 26 characters of Crockford base32 in groups (`XXXXX-XXXXX-XXXXX-XXXXX-XXXXXX`). Typing is lenient: case, dashes and spaces are ignored, `O` reads as `0`, `I` and `L` as `1`.
- **Printed once**, in one marked block of the boot log (stdout), with the addresses of the setup page. Also written to `setup-code.txt` next to the configuration file (mode 0600), deleted once setup is done. `setup.printCode: false` leaves the block out of the log (the file is still written when possible). The code is never logged otherwise.
- Only its SHA-256 is kept, in the platform store: a restart keeps a pending code valid but cannot show it again. The log says when it was issued and how to replace it.
- Valid for `setup.codeTtlHours` (24). Redeeming it is limited to 10 tries per 15 minutes per core: past that the tries answer 429 until the window ends, and the code stays valid.
- **Replace it:** `node bin/admin.js setup-code --new` on a core (shell access is the proof of being the operator; in a container, `docker exec <container> node bin/admin.js setup-code --new`), or `POST /system/admin/setup/code` with the admin key. The previous code stops working.
- **Choose it in advance** (images, CI, marketplace): `node bin/admin.js setup-code --hash` prints a new code and its SHA-256. Put only the hash in `setup.codeHash` (environment variable `pryv_setup__codeHash`, or `node bin/init.js --setup-code-hash=<sha256>`): the first boot then accepts that code and prints none. The hash is the SHA-256 (hex) of the canonical code (the 26 characters, upper case, no separator); `setup-code --hash <code>` computes it. Generate the code with `setup-code --hash`: nothing checks the strength of a code you make up.

## The built-in setup page

`/system/setup/` is served by every core, on any host name and on the bare IP address (`http://<ip>:3000/system/setup/`, or `https://<ip>/system/setup/` with TLS), in both topologies. It needs no hosted site, no DNS, no certificate and no outbound access: it is the way in when the administration portal cannot be reached yet. It answers 404 once setup is done.

The steps:

1. Enter the setup code. The page opens a **setup session** (2 hours).
2. Read the checks: configuration, public address, DNS delegation, certificates and how they are issued, migrations, second factor, registration, portal, admin key scope. Each check is `ok`, `info`, `warn` or `blocking`.
3. Sign in with an account of the platform, or create one. When administrators need a second factor (`services.mfa` on and `admin.session.requireMfa: true`), enable a TOTP factor on that account, then sign in again with it.
4. That account becomes the first administrator, with role `owner` at scope `platform`.
5. Finish. Registration opens, the setup code and the setup session stop working.

The page is three static files of the release (HTML, one script, one style sheet), with no external resource. Every answer carries `content-security-policy: default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'` and `cache-control: no-store`. The setup session and the account's token live in the page's memory only: reloading the page ends the session, and a new code is then needed (the page asks before it is left).

The page's registration asks for the basic fields only (username, email, password). A platform that requires more (extra account fields in `custom.systemStreams`, an invitation token, a proved email with `account.emailVerification.requireAtRegistration`) refuses it: create the account first with [`POST /system/create-user`](/reference-admin/#create-user) (admin key) or with the account app, then sign in with it on the page.

Signing in from the page uses the app id `pryv-setup-page`, which `auth.trustedApps` does not need to list: a sign-in with that app id is accepted when it comes from the core's own origin (the request's own host, `core.url` or `dnsLess.publicUrl`) and carries a valid setup session while setup is pending. Anywhere else the app id is checked against `auth.trustedApps` like any other.

The same steps can be scripted with the [setup routes](/reference-admin/#setup).

## Administrator sessions

An administrator authenticates to the `/system` routes with an **administrator session**, opened from a sign-in to the account:

1. The administrator signs in on the account's home core as in any Pryv.io app (password, then the second factor). The sign-in gives a personal token.
2. `POST /system/admin/session` with that personal token in the `Authorization` header and `{ "username": "<username>" }` in the body opens the session (256 random bits, `admin.session.ttlMinutes`, default 60). Only its SHA-256 is stored, in the platform store, so every core of the platform accepts it.
3. Calls carry `Authorization: AdminSession <token>`. On each request the core that serves it reads the account's role row and computes the permissions the account holds **on that core** (see [Roles, scopes and local policy](/customer-resources/admin-roles/)).
4. `POST /system/admin/session/renew` with `{ "personalToken": "..." }` extends the session; `DELETE /system/admin/session` ends it.

A session opens for any account that holds an active grant, even a grant that gives no permission on this core. The answer lists what the session holds here (`permissions`) and the permissions of its roles it does not hold here, with the reason (`denied`: `scope` or `local-policy`). An app access or a shared access of an administrator opens nothing: only a personal access does. A personal token is accepted on its account's home core only: elsewhere these routes answer an error with the home core's URL (`data.homeCoreUrl`).

**Second factor.** With `services.mfa` on and `admin.session.requireMfa: true` (the default), the sign-in behind the personal token must have passed its second factor. The home core records the account's latest second-factor sign-in in its local memory (one entry per account, lost at a restart: the administrator then signs in again). Without it the session is refused (403, `data.mfaRequired: true`).

**Step-up.** Granting or revoking roles, minting claim codes and deleting accounts (`roles:grant`, `claimCodes:mint`, `users:delete`), and writing some [platform configuration](/customer-resources/platform-configuration/) keys, need a second factor younger than `admin.session.stepUpMinutes` (default 5). Without it the call answers 403 with `data.stepUp: true`. The administrator signs in again and sends that new personal token to `POST /system/admin/session/step-up`, then repeats the call. A core accepts a second factor stamped up to 60 seconds in its future (the clock difference with the home core).

**Ending sessions.** Deleting the account's role row, or `node bin/admin.js sessions revoke <userId|username>`, stops every session of the account at its next request, on every core. A session opened before the account's role row was deleted stays refused if the account gets a role again.

**Origin rule.** A call to `/system` that carries an `Origin` header and is not authenticated by the admin key is accepted only from the core's own origin, the portal's origin (from `portal.site` and the topology, or `portal.url`) or an origin listed in `portal.cors.allowedOrigins`, and gets CORS headers for that origin only. Admin-key calls and calls without `Origin` keep the API-wide behaviour.

**dnsLess and other hosted sites.** In dnsLess every hosted site is served on the API's origin, the portal's too, and the portal keeps the administrator session in that origin's `sessionStorage`: a page of another hosted site can read it. Host there only sites you would trust with an administrator session, or use the DNS topology, where each site has its own origin. `bin/check-config.js` warns when the portal shares its origin this way.

**Refusals.** A refused credential (no credential, an unknown or ended session, a permission not held, the admin key outside its scope) answers `404 unknown-resource`, as an unknown route does.

## Claim codes

A **claim code** gives a role to the account that redeems it: same format as the setup code, role and scope fixed when it is minted, valid 15 minutes by default (24 hours at most), single use (of two concurrent claims exactly one wins).

- **Mint one** with `node bin/admin.js claim-code --role <role> --scope <scope> --ttl 15m` on a core, or [`POST /system/admin/claim-codes`](/reference-admin/#mint-a-claim-code) `{ role, scope, ttlMinutes }` with the admin key or an owner's session (step-up). Not with the setup session: a code outlives it. Without `role` and `scope` the code gives `owner` at `platform`. The code is answered once and never stored (only its SHA-256 is).
- **Redeem it:** the person signs in on the account's home core and calls [`POST /system/admin/roles/claim`](/reference-admin/#claim-a-role) with the personal token in `Authorization` and `{ username, code }`. The same second-factor rule as for a session applies. An account may try 10 codes per 15 minutes (429 past that).
- The grant records `via: claim-code` and who minted the code.

This is also how an upgraded platform, or one finished by automation, gets its first administrator: mint an `owner` code on a core's shell and hand it to that person.

Roles are stored in the platform store under the account id, never a username or an email; no credential is in them. **The last lasting owner grant** (`owner` at scope `platform`, without expiry) cannot be revoked nor replaced by an expiring one: the call answers `400 invalid-operation` with `data.id: last-owner`. `node bin/admin.js roles revoke --force` does it anyway, after which the platform is administered with the admin key and a claim code. Two revocations racing to remove the last two owners both fail.

Deleting an account deletes its role row (its sessions stop). The holder of the last lasting owner grant cannot delete that account with its own token (`400 invalid-operation`, `data.id: last-owner`); a deletion with the admin key goes through.

## The admin key: `auth.adminAccessKeyScope`

The admin key (`auth.adminAccessKey`, sent as the raw value in the `Authorization` header) still works beside administrator sessions. What it reaches depends on `auth.adminAccessKeyScope`, set in the configuration file of every core (the same value on each):

- **`full`** (the default, unchanged behaviour): the admin key authenticates every route that takes it.
- **`break-glass`**: on `/system`, the admin key reaches only the routes marked break-glass in the [Admin API reference](/reference-admin/#authentication) (calls between cores, the setup code, claim codes, role listing and revocation, status routes); a `/system` path not in the route table is refused too. Outside `/system` the key no longer deletes accounts (`DELETE /users/{username}`: the account's own token still can, when `user-account.delete` allows it) and no longer reaches `/reg/records` (use `bin/dns-records.js`) nor the `/reg/admin/*` routes. The previews cache clean-up keeps the key. Everything else needs an administrator session. A refused admin-key call answers 404.

The key cannot be retired (other secrets are derived from it): keep it for recovery. Before switching to `break-glass`, check that no script provisions accounts or writes DNS records with the key.

## `bin/admin.js`

Runs on a core's shell and talks to the platform store directly, so it works while the API is down. Shell access to a core is the proof of being the operator.

```
node bin/admin.js setup-code
node bin/admin.js setup-code --new
node bin/admin.js setup-code --hash [<code>]
node bin/admin.js setup finish
node bin/admin.js claim-code [--role owner] [--scope platform] [--ttl 15m]
node bin/admin.js roles list
node bin/admin.js roles grant <userId|username> --role <role> --scope <scope> [--expires 90m|12h|30d|<ISO date>] [--force]
node bin/admin.js roles revoke <userId|username> [--role <role>] [--scope <scope>] [--force]
node bin/admin.js sessions revoke <userId|username>
node bin/admin.js audit tail [--method <id>] [--since 90m|12h|30d|<ISO date>] [--limit <n>]
```

`setup-code` without option prints the setup state and the pending code's times; `--new` replaces the code and prints it once; `--hash` prints a code and its SHA-256 for `setup.codeHash` (no store access). `roles grant`, `roles list` and `audit tail` come with the release after 2.0.0-rc.91. `--config <file>` layers a host configuration file, as for `bin/master.js`. A username is looked up on the core the tool runs on: give the user id for an account of another core. A code is printed once: keep the output out of shared logs.

Each act of the tool (code replaced, setup finished, claim code minted, role granted or revoked, sessions revoked) is recorded in the core's [platform trail](/customer-resources/admin-audit/) and, when `audit.syslog.active`, written as one line to the audit syslog channel: the act, the role and scope, the target account id, the operating-system user and the core id, never a code.

## Configuration

| Key | Category | Default | Meaning |
|---|---|---|---|
| `setup.codeTtlHours` | platform-wide | `24` | lifetime of a setup code |
| `setup.codeHash` | bootstrap | `null` | SHA-256 of a setup code chosen by the deployer |
| `setup.printCode` | per core | `true` | print the setup code block at boot |
| `setup.registrationWhilePending` | platform-wide | `closed` | `closed` or `open` |
| `auth.adminAccessKeyScope` | platform-wide (in each core's file, never in the platform store) | `full` | `full` or `break-glass` |
| `admin.session.ttlMinutes` | platform-wide | `60` | administrator session lifetime |
| `admin.session.stepUpMinutes` | platform-wide | `5` | how recent the second factor must be for a sensitive act |
| `admin.session.requireMfa` | platform-wide | `true` | administrators need a second factor whenever `services.mfa` is on |
| `admin.localPolicy` | per core | none | see [local policy](/customer-resources/admin-roles/#local-policy) |
| `admin.lockdown` | per core | none | see [lockdown](/customer-resources/platform-configuration/#lockdown) |
| `portal.site` | platform-wide | `null` | the hosted site that is the administration portal (the install wizard writes `admin`) |
| `portal.url` | platform-wide | `null` | address of a portal hosted outside the platform (instead of `portal.site`) |
| `portal.cors.allowedOrigins` | platform-wide | `[]` | other origins a portal may call `/system` from |

Boot and `bin/check-config.js` check these keys (`portal.site` must name a configured hosted site and is not set together with `portal.url`). The portal signs in with the app id `pryv-platform-portal`: `auth.trustedApps` must accept it from the portal's origin. The install wizard adds `pryv-platform-portal@<portal origin>` when it writes a `portal.site` entry; with `portal.url`, add it yourself, or the portal's sign-in is refused.

## Moving the platform store between engines

`bin/migrate-platform.js` copies every row, the setup state, the role rows and the live codes and sessions included. Codes and sessions are stored by their SHA-256 only, so no secret moves; a pending setup code, a claim code or an administrator session stays valid on the new engine until it expires.
