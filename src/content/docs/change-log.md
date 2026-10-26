---
title: API change log
description: Release notes for the Pryv.io API, tracking breaking changes, new webhook and websocket features, storage options and version-by-version updates.
---

## 2.0.0-rc.59

External ids in forced mode, a fix of the identity host of dnsLess cores configured with `core.url` only, and a dependency security update: upgrade every core. No migration.

- **External ids: forced mode.** `externalId.mode: 'forced'` (or a namespace whose `defaultMode` is `forced`) is now accepted on `POST /reg/access` and `POST /users`; it answered `forced-mode-not-available` until now. On an auth request, only the account that holds the id receives the credential: at `ACCEPTED` the core checks that the posted token is an app access of the posted `username` and that this account holds the id, otherwise `400 external-id-mismatch` (`data: { namespace, reason: 'token-invalid' | 'not-holder' }`) and the request stays `NEED_SIGNIN`. A check that cannot run answers `503 external-id-check-unavailable`, never a pass. A forced acceptance refuses the page-made `handoff` and `externalIdDeclined` (`400 invalid-parameters`); `not-holder` refusals count in the external-id lookup budget. A forced registration with an id any account holds is refused with `409 external-id-already-claimed` (`reason: 'value-taken'`) before anything is reserved; an unclaimed id is linked. See [Forced mode](/customer-resources/external-ids/#forced-mode).
- **CMC and delegation identity host on a dnsLess core configured with `core.url` only.** The host a core presents to counterparties (CMC relationships, delegations, OAuth revoke notices) now falls back to the host of `core:url` before `localhost` when neither `dns.domain` nor a `service` block is configured. Such a core presented itself as `localhost`, which broke cross-core relationships. Every valid configuration resolves to the same host as before.
- **Security: dependencies.** `nodemailer` 10.2.1 (GHSA-8c8m-p3m8-cjg8, GHSA-m943-m63m-w62w, GHSA-85x2-q946-cp5h: address-parser flaws that could turn display text into a recipient).
- `unknown-resource` messages without an id no longer end with a space (`Unknown external id`). The error id and status are unchanged.

## 2.0.0-rc.58

External ids: a service links a third-party record id (an EHR patient id, for example) to exactly one account on the platform, without the platform ever seeing the id. Also a cross-account messaging fix and dependency security updates (denial of service in request parsing and uploads): upgrade every core. No migration; the new tables are created at boot. Runs on Node.js 24.22.1 or later, as 2.0.0-rc.57.

- **External ids: one account per record id, platform-wide.** The service sends a blinded value `HMAC(K_namespace, id)` computed with its own key. Operators create namespaces with `PUT /system/admin/ext-id-ns/<namespace>`; an account links an id with `account.externalIds.claim` (personal token), lists, replaces and releases them; `POST /reg/ext-id/cores` finds the core that holds an id. One id per account per namespace, and one account per id across all cores: a second account gets `409 external-id-already-claimed`, never told which account holds it. Lookups and refused claims share a budget of 10 a minute per client address. See [External ids](/customer-resources/external-ids/).
- **External ids in sign-in and registration (hint mode).** `POST /reg/access` and `POST /users` accept `externalId: { namespace, blindedValue, mode? }`. On an auth request, the auth page asks the user whether to link the record to the account that signs in; "Not now" posts `externalIdDeclined: true`, which the app then reads in the accepted state. A registration links the id to the new account when no other account holds it and says so in `externalIdLinked`. The `forced` mode is refused for now (`forced-mode-not-available`). See [Sign-in and registration, hint mode](/customer-resources/external-ids/#hint-mode).
- **Cross-account messaging: revoke notices.** On a `consent/revoke-cmc` arriving in `:_cmc:inbox`, the fields the receiving server owns (`superseded`, `backChannelAccessId`, `dataGrantAccessId`, `revokedAccessIds`) are always written by that server, never taken from the sender. Before, a sender could mark its own revoke `superseded`, and apps then showed a torn-down relationship as still live.
- **Native installs: replacing the bundled rqlite.** `storages/engines/rqlite/scripts/setup` no longer moves an older `rqlited` left at `var-pryv/rqlite-bin/` (installs that predate 2.0.0-rc.1) into `bin-ext/`: only a binary of the pinned version is moved, any other is renamed aside and the pinned version downloaded. Before, following the replacement steps on such a host installed that older binary, which cannot open a 10.x data directory. See [INSTALL, Upgrading the bundled rqlite](https://github.com/pryv/open-pryv.io/blob/master/INSTALL.md#upgrading-the-bundled-rqlite-9x-to-10x), which now also describes checking the new binary before stopping the core.
- **Security: dependencies.** `body-parser` 1.20.9 (GHSA-27r3-jxmh-p828, denial of service through trailing bytes after a compressed request body), `multer` 2.5.0 (GHSA-q7qp-rjg7-q26m, denial of service through a pending upload filter), `undici` 6.29.1 (GHSA-4qv8-2p9j-2685, GHSA-xjj6-f33q-929c), `fast-uri` 3.1.9 (moderate URI parsing advisories).

## 2.0.0-rc.57

Security release, runtime only: Node.js 24.22.1. No API change since 2.0.0-rc.56, no migration. Docker: pull the new image. Native installs: upgrade Node to 24.22.1 or later and run `npm rebuild` (a host held on 24.18.1 per the earlier advice must be released first: `sudo apt-mark unhold nodejs`); a native host can take the Node upgrade before this release, 2.0.0-rc.56 runs on 24.22.1 too.

- **Security: Node.js 24.22.1.** The Docker image moves from Node 24.18.1 to 24.22.1, which carries the Node.js security release of 2026-10-21: four high-severity fixes, among them an out-of-bounds write in the Brotli decoder that can lead to remote code execution, two TLS certificate hostname check bypasses and `dns.resolve` truncating names at a NUL character. The server decodes the responses of its outbound HTTP calls (consent counterparties and webhook targets among them), so the Brotli flaw is reachable. `engines.node` is now `>=24.22.1 <25.0.0`; the server warns at boot and `bin/check-config.js` reports a problem on an older Node. The SQLite abort on Node 24.19 to 24.21 (nodejs/node#65446), the reason for the earlier 24.18 pin, does not occur on 24.22.1 ([#162](https://github.com/pryv/open-pryv.io/issues/162)). See [INSTALL, Node major bumps](https://github.com/pryv/open-pryv.io/blob/master/INSTALL.md#node-major-bumps-v2--v2).
- **Dependencies.** `follow-redirects` 1.16.1 (GHSA-8r9p-f939-6h3c, GHSA-q3jh-wrc6-jgq8), reached through the ACME client.

## 2.0.0-rc.56

Security release: upgrade every core. It closes authorization gaps in the consent (CMC) and account-delegation namespaces and in the account-field checks, refuses calls to a counterparty that would reach a private address, and tightens stream moves. Operators still on 2.0.0-rc.53 to rc.55 who cannot upgrade at once can set `cmc.retryLoop.enabled: false` and restart until they do: while it is off, a consent delivery that fails is not retried later and expired group memberships are not swept (member accesses end at their own expiry); set it back to `true` after the upgrade. This setting covers only the retry-queue part: the other fixes in this release (the reserved-region and account-field checks, the counterparty destination guard, stream moves) have no configuration workaround and need the upgrade. No migration.

- **Security: store-prefixed stream ids.** A stream id has store-prefixed spellings that address the same stream (`:local:<id>` for `<id>`, `:account::system:<field>` for `:system:<field>`). Every guard now judges the canonical spelling: the plugin-managed regions of `:_cmc:` and `:_delegation:` (a `streams.create` or `streams.update` with a `parentId` inside them is refused, `400 invalid-operation`, `cmc-reserved-stream` / `delegation-reserved-stream`, for every token; a plugin-managed stream cannot be moved or trashed), and the account fields on `events.create`, `events.update`, `events.delete`, `accesses.create` and `accesses.update` (an id routing to the account store that names no known account field is an unknown stream; a permission given through an alias is stored under the canonical id). Requests that use the canonical ids are unchanged.
- **Security: the CMC retry worker runs only records the server wrote.** Any other event in the internal retry stream is retired without being processed.
- **Security: calls to a counterparty.** Consent deliveries, chat, revocations, scope updates, the capability read of an accept, delegation notices and OAuth revocation notices are refused before any connection when the URL's host is or resolves to a loopback, private, link-local or otherwise reserved address, uses `http:` (unless `cluster.allowInsecurePeerUrl`) or carries credentials, and when the answer is a redirect or larger than 1 MiB. The platform's own host names are always allowed; peers on a private network go in the new `cmc.allowedPrivateHosts` (host names, IPs or CIDR ranges, as `webhooks.allowedPrivateHosts`). A refused delivery is permanent: `cmc-handler-destination-refused`, or `cmc-capability-destination-refused` when an accept's offer read is refused.
- **Security: moving a stream.** `streams.update` with a new `parentId` by a non-personal access needs manage rights on the whole moved subtree as well as on the target parent (`403 forbidden` otherwise); a `parentId` naming one of the stream's descendants is refused (`400 invalid-operation`).
- **Withdrawing a single-use invite.** `consent/invalidate-link-cmc` now withdraws a single-use invite nobody accepted yet ([#160](https://github.com/pryv/open-pryv.io/issues/160)): the trigger's `content.status` becomes `invalidated` and a later accept fails with `cmc-capability-invalidated`; on an accepted invite it stays a no-op. The offer text stays readable through the link until it expires, so set a short `expiresAt` on invites you may withdraw. Clients that enumerate invite statuses: `invalidated` is no longer open-link only.
- **Usernames and platform names.** Registration, the username check and change, admin pre-registration and delegated account creation refuse a name equal to a core id, a `dns.staticEntries` key or a runtime DNS record; a new DNS record or core id under an existing account's name is refused (`POST /reg/records` answers `409 item-already-exists`).
- **Access deletion records (operators).** New per-core setting `accesses.deletionRecords.retentionDays` (default 0, kept until the account is deleted): above 0, deletion records older than that are purged once a day, after which audit pages show such an access by id only.

## 2.0.0-rc.55

Docker image on Debian 13 with rqlite 10.6.0, log masking hardened, and a core without an SMTP host now treats mail as not configured instead of logging an error for every registration. Operators of native installs: replace the bundled `rqlited` binary yourself (below). No migration.

- **Docker image: Debian 13 (trixie).** The image is based on Debian 13 instead of Debian 12 (bookworm), with the same Node 24.18.1: Debian 12 left its remaining critical and high OS-package advisories unfixed. Images built `FROM pryvio/open-pryv.io` that `apt-get install` packages now resolve them against trixie.
- **rqlite 10.6.0.** The image bundles rqlite 10.6.0 (was 10.5.1). Within 10.x no data-directory step is needed; in a cluster, upgrade the followers first and the leader last. Native installs: `storages/engines/rqlite/scripts/setup` now pins 10.6.0 and checks the download's sha256, but never replaces an existing binary, so replace `bin-ext/rqlited` yourself while the core is stopped. See [Upgrading the platform DB's rqlite](/faq-infra/#how-do-i-upgrade-the-platform-dbs-rqlite-to-10x) and [INSTALL, Upgrading the bundled rqlite](https://github.com/pryv/open-pryv.io/blob/master/INSTALL.md#upgrading-the-bundled-rqlite-9x-to-10x).
- **Security: log masking hardened.** Credential keys (`token`, `password`, ...) and `auth=` / URL credentials are now masked in contexts that were written as is: a context holding a BigInt (the JSON console also threw on it), and a context that cannot be turned into JSON (a circular object such as an HTTP request, or one whose `toJSON` or a getter throws). In such a context a cycle shows as `[Circular]`, an unreadable branch as `[Unserialisable]`, nesting beyond 32 levels as `[Too deep]` and what lies beyond 20,000 values as `[Truncated]`. A message that is not a string (such as a URL holding a token) is masked like a text message, a function logged as context prints as `[Function: name]`, and credential keys inside a text (a logged JSON body) are hidden whatever their case, for every key hidden as an object property (adding `secret`, `key`, `authorization`, `cookie`, `set-cookie` and others). Contexts that convert to JSON print as before.
- **Logs: Error contexts in the log file.** An error logged with its Error object carries the error's name, masked message and stack in the `context` field of `logs.file` (it was `{}`), as the JSON console does since 2.0.0-rc.54.
- **Logs: no boot-time `[winston]` line.** A process start no longer prints `[winston] Attempt to write logs with no transports ...` when no `logs.custom` is configured. Nothing was lost.
- **Mail without an SMTP host: not configured.** With in-process mail (`services.email.method: in-process`, the default) and no SMTP host (`services.email.smtp.host` unset, or a placeholder such as `REPLACE ME` as on a fresh install), the core logs one warning at boot naming the mail classes that are switched on but not sent, and skips those mails quietly; registrations and password resets no longer log an `unexpected-error (500)` each. `POST /:username/account/request-password-reset` answers 200 with no mail sent (it failed with `500 unexpected-error`), and `POST /system/admin/mail/send-test` answers `503 api-unavailable` ("Mail is not configured: ...") instead of `500 unexpected-error`. A configured SMTP host keeps the previous behaviour: a delivery failure is still logged as an error. See [Without an SMTP host](/customer-resources/emails-setup/#without-an-smtp-host).

## 2.0.0-rc.54

Logging for operators: a core with no log target configured, such as one installed with an earlier install wizard, now writes its warnings and errors to stderr instead of dropping them; production console logs carry no ANSI colour codes; the master's messages appear once, with a new prefix (adjust any grep on `[master] WARNING:` or `[master] ERROR:`). No migration.

- **Logs: warnings and errors are never silent.** When no log target is configured (`logs.console`, `logs.file`, `logs.fileSync` and `logs.custom` all inactive), the master and the workers write their warnings and errors to stderr, so the journal or `docker logs` keeps them. Until now such a core logged nothing but the master's own lines: a configuration without a `logs:` section, as written by the install wizard, turned every worker error into silence. Any configured target keeps the previous behaviour. See [Where do the core's logs go?](/faq-infra/#where-do-the-cores-logs-go)
- **Logs: no colour codes in production.** Console logs carry no ANSI colour codes in the journal or `docker logs` with the production defaults (`NODE_ENV=production`, the Docker image default), with a wizard-generated configuration and with the stderr fallback above. The setting is `logs.console.format.color` (default `true`, kept for interactive development); the `logs.console.colorize` key the production defaults used was never read: a configuration that still sets it should switch to `format.color: false`.
- **Logs: master messages once, new prefix.** The master process's messages appear once, through the logger, instead of twice (a logger line plus a raw console copy). Their text is unchanged, the prefix changes: `[master] WARNING: <msg>` is now `[warn]: [master:master] <msg>`, `[master] ERROR: <msg>` is `[error]: [master:master] <msg>` and `[master] <msg>` is `[info]: [master:master] <msg>`, with the console's timestamp. A grep on the message text (such as `Master process ready`) still matches. The master's info lines follow `logs.console` like every other line; a boot failure before the logger is ready still prints `[master] FATAL: ...` on stderr.
- **Logs: Error contexts in JSON logs.** With `LOG_FORMAT=json` (or `logs.console.format.json`), an error logged with its Error object carries the error's name, message and stack in `context` (it was `{}`).
- **Install wizard: a `logs:` section.** The `pryv-config.yml` written by `init` now has a `logs:` section, as in the production defaults: the console at `info` without colours, and errors in a daily file `<data folder>/logs/api-server.errors.log` (14 days kept) on the data volume. Configurations written by earlier versions can add the same section. See [Where do the core's logs go?](/faq-infra/#where-do-the-cores-logs-go)

## 2.0.0-rc.53

Group accounts in consent (CMC), with `@pryv/cmc` 3.21.0, and behaviour changes for every CMC deployment: revoke notices the other core could not take are re-sent, the CMC retry loop now runs by default (`cmc.retryLoop.enabled: true`), and every consent and delegation teardown is now the `accesses.delete` deletion. Operators: before upgrading a core that ran with the retry loop off, size its retry backlog; records older than their schedule are retired, not replayed. No migration.

- **Group accounts.** A practice, a research team or a bridge shares one Pryv account. Its members join it from their own accounts (`consent/request-cmc` with `request.membership: true`), and each member reads a patient's data under a short-lived access that names them, created by the group's core on the patient's core through the patient's delegable consent grant (new event type `consent/member-access-cmc`). When a membership ends (revoked, left, expired, narrowed, detached), those accesses are deleted on the patients' cores and the offboarding is recorded (new event type `consent/member-revoke-cmc`). The group's and the members' cores need this release; a patient core of an earlier release gets attribution by name only (`cmc.memberAccess.allowNameOnly`). New `cmc.memberAccess.*` settings on the group's core. See [Group accounts](/guides/group-accounts/), and the reference member app [app-web-group-member](https://github.com/pryv/app-web-group-member).
- **Revoke notices are re-sent until they land.** A `consent/revoke-cmc` whose counterparty could not be reached (network error, timeout, 5xx) is queued and re-sent after 1, 5 and 25 minutes, about 2 hours, then every 6 hours (8 re-sends over about 27 hours), then marked `failed-permanent` for the operator; the event reports `content.deliveryQueued: true`. A raw `accesses.delete` of a relationship access and a delegation detach queue their notices the same way. Not queued: the notices sent while an account is being deleted ([#157](https://github.com/pryv/open-pryv.io/issues/157), a known limitation). A late notice never ends a relationship accepted again meanwhile: it names the accept it ends (`content.acceptEventId`, `content.revokedAt`), and such an arrival is marked `content.superseded: 'relationship-re-established'`. See [Revoking](/guides/cross-account-messaging/#revoking).
- **Behaviour change: the retry loop is on by default.** `cmc.retryLoop.enabled` now defaults to `true` on every core; set to `false`, nothing is queued and a warning is logged at boot. When the loop starts, a pending record older than its whole schedule (2 hours for a trigger, 30 hours for a revoke notice) is retired as `failed-permanent` with `lastFailureReason: 'cmc-retry-stale'` and never sent. Settled records are pruned, an account with nothing pending is read every 10 minutes instead of every minute, and in a cluster the loop moves to the replacement of a crashed worker (it ran on worker 1 only and stopped for good when that worker restarted). New `cmc.retryLoop.startScheduler`. See [Retries and the retry loop](/guides/cross-account-messaging/#retries-and-the-retry-loop).
- **Behaviour change: consent and delegation teardowns are `accesses.delete`.** Accesses the server removes (a revoke written or received, a delegation detach, the teardown at account deletion, a collected capability, a member offboarding) were removed outright. They are now deleted as `accesses.delete` does: listed by `accesses.get` with `includeDeletions: true` (name kept, token never), their webhooks deleted, their aliases released. Apps that list deletions will see these records. A new accept after a revoke creates a new access.
- **Offers refuse the streams the plugin manages.** A `consent/request-cmc` asking for `:_cmc:inbox`, the `:_cmc:_internal` subtree, a chats or collectors stream or the `:_cmc:apps` root is refused at write (`cmc-invalid-event-content`) and again at accept (`cmc-offer-stream-not-offerable`). `consent/invalidate-link-cmc` must be written on the invite's stream or above it (`cmc-invalidate-link-scope-mismatch`). See [Streams reserved by the plugin](/guides/cross-account-messaging/#streams-reserved-by-the-plugin).
- **Accesses.** An app token may delete only the `shared` accesses it created (`403 forbidden` otherwise), and `accesses.update` can no longer remove `clientData.cmc` from an access that carries it (`cmc-clientdata-cmc-forbidden`).
- **Delegation and invites.** A membership approved by a delegate administrator ends with that delegation. A directed invite (`content.to` on `consent/request-cmc`) is recorded, never delivered: hand over the capability URL.
- **Mail templates without a restart.** With `services.email.method: in-process`, a template written or deleted through the admin API is used by every worker of the serving core from the next mail on; when the serving worker cannot reload, the request answers `503 api-unavailable` (the template is stored: repeat the request). The other cores use it from their next start, and `bin/mail.js` writes still need a restart ([#159](https://github.com/pryv/open-pryv.io/issues/159)). See [Managing templates: admin HTTP API](/customer-resources/emails-setup/#managing-templates--admin-http-api-).
- **Operator tools log to stderr.** `bin/mail.js`, `dns-records.js`, `breach-scope.js`, `integrity-check.js`, `observability.js` and `oauth-client.js` write their logs to stderr, so their stdout holds only their output. Scripts that read these logs from stdout must read stderr.
- **Event types 1.3.0.** The catalogue bundled with the server adds the event types and fields of group accounts and of the revoke notices. See [Event types](/event-types/).
- **Erased accounts stay erased on disk.** A request still holding the id of an account being erased (a sign-in in flight, for example) no longer re-creates an empty per-user directory and database for it; such a request now fails instead.

## 2.0.0-rc.52

Two security fixes in consent (CMC) and delegation: upgrade promptly. Operators: after deploying, run `node bin/access-scope-audit.js` (read only) to list the sub-accesses that earlier withdrawals left behind, and review them with the account owners. No migration.

- **Security fix: withdrawing a consent ends its sub-accesses.** A delegable consent grant (offer `request.accessType: 'app'`) lets the requester create `shared` sub-accesses. Until this release only a plain `accesses.delete` of the grant took them with it: a `consent/revoke-cmc` written by either side, a revocation received from the counterparty, the end of a delegation and the deletion of the counterparty's account removed the grant alone, and the sub-accesses kept opening the data until their own expiry. Every path now removes them first. Sub-accesses left behind earlier are not removed automatically: `bin/access-scope-audit.js` lists the live accesses whose creator is gone under "no longer managed". An access created under a caller id (`createdBy: '<id> <callerId>'`) is now matched on its creator's id, so `accesses.delete` of the creator removes it and the creator can list and delete it.
- **Security fix: a delegate no longer reads the owner's credentials.** Wherever an access is returned without its token (a delegate's reads of the owner's accesses), every URL inside its `clientData` comes without its user part, such as the counterparty endpoints of a consent relationship; host and path are kept. A webhook returned to a caller that neither owns its access nor created it carries its `url` reduced to scheme, host and path (user part, query and fragment removed). The owner's own reads are unchanged. Deletion records are redacted the same way for every caller, and the URL credentials leave the stored row and its history once the access is deleted.
- **Logs: size cap.** `logs.file.rotation.maxSize` (for example `"10m"`) caps the size of each daily log file; unset by default. Remove `logs.file.maxFileBytes` and `maxNbFiles` from your config: they never applied. Setting `maxSize` starts a new list of files to prune, so delete the earlier daily files once by hand.
- **Pre-registration.** `POST /system/users/validate` (admin) refuses a username that account creation would refuse (`400 invalid-parameters-format`) before reserving anything or consuming the invitation token.

## 2.0.0-rc.51

Backup operators: check every directory that received `bin/backup.js --incremental` from an earlier release. It is damaged (it holds only the last delta, nothing in it can be repaired) and its restore is now refused: take a new full backup into a new directory and continue with `--incremental` from there. Full backups written by earlier releases are not affected. A configuration declaring `custom.systemStreams.other` entries now refuses the boot.

- **Backups: incremental runs form a chain.** An incremental run writes its own `incrementals/<runId>/` directory (own manifest, own `encryption.json`) next to the full backup, listed in `chain.json`; it no longer overwrites the full backup, whose restore reported success with only the last delta. `--restore` applies the full backup then every run in order (`--through-run <runId>` stops at a given run), `--inspect <dir>` says whether a directory is sound (`DAMAGED` for one written by an earlier `--incremental`; `--allow-incomplete` restores that delta anyway). A run's window starts at the previous run's snapshot (nothing changed during a run is missed), deletions of streams, accesses and webhooks are carried, an account deleted between runs is not re-created, an emptied series stays empty, and an encrypted chain is continued with the same key model (checked before anything is written). Two overlapping runs into one directory: the second to finish is refused and left aside. On a chain, use the newest run's `decrypt-backup.mjs`. `node bin/backup.js --help` prints the tool's usage. See [Incremental backup](/customer-resources/backup/#incremental-backup).
- **Configuration, BREAKING: no custom other system streams.** A config declaring any entry under `custom.systemStreams.other` is refused at boot and by `bin/check-config.js`. Such streams had no storage: `streams.get` did not return them and no event could be written in them. Remove the section (an empty list is accepted); account fields belong under `custom.systemStreams.account`. See [System streams](/customer-resources/system-streams/#no-custom-other-streams).
- **Audit and event reads on SQLite.** `events.get` on the audit streams (such as an account export over `:_audit:accesses` and `:_audit:actions` with an open time range) walks the time index and stops at `limit`, instead of scanning and sorting the whole audit file and stalling the API worker for minutes on a large one ([#156](https://github.com/pryv/open-pryv.io/issues/156)). The same applies to `events.get` with `streams` `*` (or no stream filter) on the SQLite event store. Results are unchanged.
- **SQLite: replaced account files.** A running core now reads an account's `account-1.0.0.sqlite` that a restore (or another process) deleted or replaced; it kept reading the deleted file, and changes made in that window were lost.
- **Login and MFA.** A login refused after its MFA session was opened ends that session, so it no longer holds one of the account's pending places until it expires. Two concurrent failed `mfa.activate` calls no longer discard the enrolment pending before them.
- **Docker images: `latest`.** `pryvio/open-pryv.io:latest` and `pryvio/open-pryv.io-encrypted:latest` follow every release tag, release candidates included; `pryvio/open-pryv.io:latest` still pointed at the v1 image (1.7.1). Production deployments should keep pinning a version tag.

## 2.0.0-rc.50

Hardening of API inputs and query semantics, notifications, registration, access requests and account deletion; several refusals are visible to clients (listed below). Before deploying, operators can count, read only, what the new rules touch: local events naming an account stream next to another stream, accesses granting `:_system:account` above `read`, and usernames of the shapes now reserved. A core configured with `integrity.algorithm: md5` or `sha1` refuses to boot. The Docker image no longer ships `npm` / `npx`.

- **Stream queries.** An `all` entry that resolves to no stream (unknown, or also excluded by `not`) now makes the query match nothing; it was ignored. The same holds for webhook and Socket.IO scopes. A store root (`:local:`, `:<store>:`) stands for `*` and may only appear alone in `any`; a malformed store prefix (`:abc`, `::x`) is refused with `invalid-request-structure`.
- **`events.get`.** `fromTime`, `toTime` and `modifiedSince` must be finite numbers (`invalid-parameters-format`). SQLite cores now behave as PostgreSQL cores: `skip` without `limit` pages the result, and deletions with `modifiedSince` are paged, ordered by `sortAscending`, with a strict bound.
- **Deletion records only for whole-store readers.** `events.get?includeDeletions` and `streams.get?includeDeletionsSince` return deletions only to a personal access or a `*` read access with no `none` / `create-only` exception; others get an empty list (with `versioning.deletionMode: keep-everything`, the event deletions whose kept streams they can read). A lib-js `Monitor` on a stream-scoped app token therefore no longer receives final deletions; trashing still arrives as an update.
- **Account fields written through events.** `events.create` / `events.update` on an account field (`:_system:language`, editable custom fields) follow the field's own rules (`language` 1 to 5 characters, the field's `regexValidation`, strings of at most 300 characters, finite numbers; `invalid-parameters-format`) and take the server time, ignoring a client `time`. An event naming an account stream next to another stream is refused with `invalid-operation`. A unique custom field releases its previous value once the new one is written.
- **Accesses and streams.** `:_system:account` can be granted at `read` or `none` only (`invalid-operation`): grant the fields themselves to write them. `accesses.get`: `includeDeletions` and `includeExpired` must be booleans, and `includeDeletions=false` leaves deletions out. `streams.create` refuses an id naming a built-in object property (`constructor`, `__proto__`, `toString`, ...) with `invalid-item-id`.
- **HTTP.** Urlencoded requests: `_method` must be `GET`, `POST`, `PUT` or `DELETE`, `_json` must hold an object or array, and `_auth` / `_method` may not repeat (`invalid-request-structure`). An `auth` query parameter that is not a single string answers `401 invalid-access-token`. Query-string keys naming built-in object properties are ignored; a `__proto__` key in a profile, an event `clientData` or a webhook scope name is kept as an ordinary entry.
- **Notifications.** Scoped Socket.IO subscriptions and webhooks cover streams created or moved after they were set. A socket connected through an alias of the account receives its notifications. `accessUpdated` goes only to the sockets of the updated access (the others still get `accessesChanged`). A `/<username>/<username>` namespace must name the same account twice.
- **Webhooks.** Each webhook is called once per change (it was called once per API worker). Scopes follow their access: narrowed by `accesses.update`, a scope the access no longer reaches is removed, and a webhook left without scopes turns `inactive`. `webhooks.update` with `scopes` replaces the map and applies at once. Deleting an access or an account stops its webhooks at once, and a renamed account's webhooks keep firing. `webhooks.test` is allowed once per `minIntervalMs` per webhook (`429 too-many-attempts` with `Retry-After`).
- **Access requests and OAuth2.** On `POST /reg/access/:key`, the first decision wins: the same decision again gets the stored outcome, a different one `409 invalid-operation`. Polling keys are 32 characters. `POST /access/invitationtoken/check` allows 10 checks a minute per address (`429`). OAuth2 PKCE: the S256 `code_challenge` must be 43 base64url characters and `code_verifier` must follow RFC 7636 (`invalid_request`).
- **Registration and accounts.** New usernames whose 3rd and 4th characters are `--` (`xn--...`) or of the shape of a minted alias (`r-` and 8 letters or digits) are reserved; existing accounts are not affected. `delegations.createAccount` applies the registration rules (`400 delegation-invalid-username`, `409 delegation-username-taken`). `emails.resend` refuses an address another account has proved. An account created without an email and then given one stores it as its primary email (accounts already in that state: set the email again). An account that is the delegate of an account without email cannot be deleted with its personal token (`invalid-operation`, `data.controlledAccountsWithoutEmail`) until that account has an email, as it would be left with no way in; new route `POST /{controlled}/delegations/controlled-side/status` lets the delegate's core check it across cores.
- **Sessions, previews and hosted sites.** A personal session is extended only by a call that passed every check, including the custom auth step. A preview of an image declaring more than `eventFiles.previewsMaxInputPixels` (default 100 000 000) answers `413 payload-too-large`. A proxy hosted site refuses a path with an encoded `/` or `\`, a `.` / `..` segment or a malformed percent-encoding (`400`).
- **Operators.** `integrity.algorithm` accepts `sha256` and `sha512` only. The boot log and `bin/observability.js show` give the admin key as `auth.adminAccessKey.fingerprint` (an HMAC keyed by `auth.filesReadTokenSecret`), so the snapshot hash changes once. New log files are created `0640` in `0750` directories, and more values are masked (errors, more credential names, URL user info, `DEBUG=pryv:*` output). `bin/check-config.js` reads keys set as environment variables ([#155](https://github.com/pryv/open-pryv.io/issues/155)). Joining a cluster with `--bootstrap` writes `bootstrap-config.yml` and no longer replaces `override-config.yml`. MFA SMS: new `sendLimits.perCorePerHour` (default 100), and `perDestinationPerDay` is counted platform-wide. Admin routes check their input (invitation `count`, the target core of a rename) and never take over another core's username mapping or another account's unique value; a restore refuses usernames that are unsafe or that the platform routes itself; boot warns when an access may stay cached above 300 s. Previews render at most `eventFiles.previewsRenderConcurrency` (2) at once, the image sets `UV_THREADPOOL_SIZE=16`, crashing workers are replaced with a growing delay, and `bin/backup.js` warns about plaintext backups and takes `--passphrase-file`.

## 2.0.0-rc.49

Hardening release. Client-visible: JSON answers carry `Cache-Control: no-store` and `Vary: Origin`, a path id always wins over an `id` query parameter, and HF series points and bounds are checked strictly. Operators: backups, `bin/breach-scope.js --output` reports and the `config-to-env` env file are now written owner-only (`0600`), so adjust any process that reads them as another user; a restore refuses a backup whose user ids or names are not one safe file name, or that keeps data behind symbolic links.

- **HTTP: cache directives.** Every JSON answer carries `Cache-Control: no-store` (unless the route sets its own, as the OAuth2 discovery document does) and `Vary: Origin`; preflight answers also vary on `Access-Control-Request-Method` and `Access-Control-Request-Headers`. Attachments, previews and the HTML root page are unchanged.
- **HTTP: path ids.** Routes that take an id in the path (`/accesses/{id}`, `/events/{id}`, `DELETE /streams/{id}`, `/webhooks/{id}`, `POST /webhooks/{id}/test`) always act on it; an `id` query parameter used to replace it.
- **Accesses.** Deletion records in `accessDeletions` no longer carry the deleted access's `token` or `apiEndpoint`. `accesses.checkApp` matches a feature permission only against the same `feature` and `setting` (a changed setting now answers `mismatchingAccess`), and a request with a feature permission that matches no access gets `checkedPermissions`.
- **HF series.** A non-finite or out-of-range `deltaTime` / `timestamp`, a `deltaTime` string that is not a plain decimal, a non-finite number field and an empty `points` list are refused with `invalid-request-structure`. Two points with the same `deltaTime` in one request keep the last, on every engine. `fromDeltaTime` / `toDeltaTime` given as a list or an object are refused.
- **Events.** Time bounds on account events now match other events (`toTime` inclusive, `modifiedSince` strict). On SQLite cores, a type wildcard (`note/*`) no longer matches classes with the same prefix (`notebook/...`).
- **Fresh installs.** An unset `service.assets.definitions` now defaults to the public Pryv assets instead of a path the core does not serve, which broke lib-js `ServiceAssets` and the login button. The install wizard asks for it and, in dns-active mode, adds `https://reg.<domain>` and `https://access.<domain>` to `auth.trustedApps`.
- **Operators.** The embedded DNS answers `reg.`, `access.`, `mfa.` and `lsc.` with available cores only (a pre-registered core waits for its join to be acknowledged). Logs mask `code` / `state` query values and the `Referer`, and parameter validation errors no longer log the rejected value. The per-address password-reset budget counts an IPv6 address toward its /64. A custom system stream named like a built-in account field refuses the boot. The S3 attachment engine refuses ids that are not one key segment. `POST /reg/records` answers `400` to a body that is not an object.
- **Fixes.** `callBatch` counts only existing methods in the access usage statistics; a custom indexed account field's `default` is indexed at registration; a failed `accesses.update` (and consent or delegation access changes) drops the access from every worker's cache; account deletion checks the previews directory before deleting and reports a failed removal once all removals end; a registration that lost its username to a concurrent one no longer releases the holder's verified secondary address.

## 2.0.0-rc.48

Operator step, once per core after the upgrade: `node bin/events-stamp-backfill.js --dry-run` (counts the events written without change tracking), then the same command without `--dry-run`.

- **Server-written events carry change tracking.** Events the platform writes on the user's behalf (consent inbox copies and scope-update records, account email records, delegation records) now carry `created`, `createdBy`, `modified` and `modifiedBy`, with `system` as the access id, and the status changes the platform makes to existing events (consent request and trigger status, delegation records, consent withdrawals) set `modified` and `modifiedBy: system`. `modifiedSince` syncs now return them. `createdBy` / `modifiedBy` may therefore read `system` on events, as they already could on accesses: see [Event](/reference/#data-structure-event). Not a breaking change.
- **Events kept by `streams.delete`.** Events moved to the parent stream (`mergeEventsWithParent`), or left in their other streams, get a fresh `modified` and the deleting access as `modifiedBy`, so `modifiedSince` syncs see the change.
- **Shared secrets.** An item consumed or discarded at retrieval records `system` as `modifiedBy`; it kept the creating access.
- **Operator step.** `bin/events-stamp-backfill.js` stamps the existing rows (`--config <host config>` on each core of a multi-core platform; safe to re-run, no restart needed). Each repaired event is returned once by the next `modifiedSince` sync of each client and gets a new `integrity` value.
- **Fix.** The `consent/scope-update-cmc` record written when a relationship access is changed with `accesses.update` lands on that relationship's own collectors stream; under a nested scope it went to a stream that does not exist and could not be read.

## 2.0.0-rc.47

Security release: upgrade promptly, and read the client-visible refusals first. Operators: the new per-address limits read the client address through `http.trustedProxies` only, so behind a reverse proxy list it there; once after the upgrade, remove the 32-hex upload temp files earlier versions left in the OS temp directory; `bin/emails-unproved-report.js` (read only) lists the pending email claims that still hold an address.

- **Security, BREAKING for some clients: credential methods on their own routes only.** `auth.login`, `auth.register`, `auth.emailChallenge`, `auth.emailChallengeVerify`, `account.requestPasswordReset`, `account.resetPassword`, `account.verifyEmail`, `mfa.recover` and `sharedSecrets.retrieve` answer `400 invalid-operation` inside a batch call or over socket.io. `account.changePassword`, `mfa.activate`, `mfa.confirm` and the other methods stay batchable.
- **Batch calls.** A batch holds at most 1000 calls (`400 invalid-parameters-format`), a nested `callBatch` is refused in its slot, and the results of one batch are bounded by `limits.batch.maxTotalItems` (default 100000, `413 too-many-results`).
- **Security: failed passwords are delayed, never locked out.** Sign-in, `account.changePassword`, the MFA step-up by password and `mfa.recover` share one tally per account: after `auth.passwordAttempts.freeFailures` (5) failures within `windowSeconds` (900), the next attempt answers `429 too-many-attempts` with `Retry-After` and `data.retryAfterSeconds`, for a delay doubling from 2 s up to 300 s; a success clears it. The same failures also count per client address (an IPv6 address toward its /64) across cores: past `perIp.maxFailures` (30), password checks from that address answer `429` until the window ends. See [Limits at a glance](/customer-resources/rate-limiting/#limits-at-a-glance).
- **Account deletion ends the account's relationships.** As a delegate: on each account it controlled, its tokens, control access and grants are removed and the name can be invited again. As a controlled account: its delegates' lists drop it. Cross-account consent counterparties receive `consent/revoke-cmc`. A delegation records the delegate's account id: an account that later takes the name is refused (`delegation-delegate-mismatch`), `delegations.issueToken` answers `410 delegation-not-active` once the delegate is gone, and the relationship turns `stale` until the owner removes it. New controlled-side route `POST /<username>/delegations/controlled-side/release`.
- **Email addresses.** An address added with `emails.add` no longer reserves it on the platform until it is verified; the first verification takes it, and a link for an address another account now holds answers `401 invalid-access-token`. With `account.emailVerification.requireAtRegistration`, the legacy `email` field of `account.update` accepts only an address already verified on the account. Two accounts setting the same unique value at once: one gets `409 item-already-exists`.
- **Errors.** An `unexpected-error` (`500`) no longer carries the fault's text: its `message` is `Unexpected error (ref <8 hex characters>)`, the reference of the server's log line. Do not parse it. HF series routes answer the same error.
- **Parameters and limits.** `events.get` refuses a `limit` or `skip` that is not an integer from 0 to 100000. `streams.get` refuses undeclared parameters (`id`, `storeId`, `includeTrashed`: use `parentId` and `state: 'all'`). `accesses.create` refuses a token named like a built-in object property (`invalid-item-id`). An upload carries one event part and at most `uploads.maxFiles` (10) files. A socket.io namespace is `/<username>` or `/<username>/<username>` only, and messages are bounded by `socketIO.maxMessageBytes`. An account holds at most `services.mfa.sessions.maxPendingPerUser` (5) pending MFA logins. `POST /reg/access` allows `access.maxLiveRequestsPerIp` (50) live requests per address on a core (`429`), and an unread request lives `access.unopenedRequestTtl` (600 s).
- **Security: more fixes.** An access's excluded streams stay excluded when trashed. Concurrent requests of one token never see its restrictions missing. A malformed OAuth2 signed `state` answers `400`. Each password hash gets its own salt. Account deletion erases the HF series stored under every name of the account, and a username change or a deletion drops the pending password-reset requests of the former names. Access-request keys stay out of the logs. A restore given a decryption secret refuses a plaintext backup (`--allow-plaintext`, `--require-encrypted`). Previews follow a replaced or removed attachment.
- **Fixes.** Account deletion no longer takes minutes on a core that is not the platform database leader. A dns-active core with the default `core.id: single` serves its root routes on `https://single.<domain>/`.

## 2.0.0-rc.46

Security release: upgrade promptly. Before restarting a dns-active core, check its stored DNS records with `node bin/dns-records.js list`.

- **Security: embedded DNS server.** Stricter request validation, size-limited answers (truncated over UDP), at most `dns.tcpMaxConnections` TCP connections (default 64), and validated stored records: they are normalised (lowercase, no trailing dot) when loaded, and a record that still does not validate is not served and is named once in the master log. A record holds at most 32 values per key (`a`, `aaaa`, `txt`) and 64 per subdomain (`/reg/records`: `400`). On the first boot of a dns-active core, a `dns.publicIp` that is not an IPv4 address stops the boot.
- **Security: events.** `events.get` never returns events of internal plugin streams, whatever stream ids are queried. `events.create` and `events.update` validate their attachment parameters more strictly (`events.update` takes `id` and `update` only).
- **Security: socket.io.** A call whose reply argument is not a function is answered without affecting the server.
- **Audit: `audit.onUserDelete: keep` on SQLite.** The per-user audit now stays after an account deletion with the SQLite audit engine too (the file stays in the user directory, readable by user id); it was erased with the directory. `erase` (default) is unchanged ([#154](https://github.com/pryv/open-pryv.io/issues/154)).

## 2.0.0-rc.45

Security release: upgrade promptly. Before restarting each core, run `node bin/check-config.js` with your override: a node with `core.ip` set and no Raft TLS now refuses to start.

- **Multi-core, BREAKING: Raft TLS required.** A node with `core.ip` set that runs its own rqlited and has no `storages.engines.rqlite.tls` refuses to start (it was a boot warning), single-core included. Multi-core: run `node bin/bootstrap.js init-ca-holder` on the CA-holder core (joiners get `tls` from their bundle). Single-core dns-active: remove `core.ip` and set `dns.publicIp`. `check-config` reports it as a problem.
- **MFA, BREAKING: the step-up is always required.** The one-release opt-out `services.mfa.stepUp.required` is removed: a configuration that still sets `services.mfa.stepUp` boots with a warning saying it is ignored. `mfa.confirm` is refused when the enrolment changed after its `mfa.activate`.
- **Accesses: `webhooks` feature permission.** An app or shared access carrying `{ feature: 'webhooks', setting: 'forbidden' }` cannot create, update or test webhooks (`403 forbidden`), its webhooks no longer fire, and every access it creates carries the same entry. Meant for tokens handed out publicly.
- **Security: webhooks.** `webhooks.get` with a shared access lists only the webhooks that access created.
- **Security: admin pre-registration.** `POST /system/users/validate` consumes the invitation token (given back if the reservation fails), refuses reserved names, requires `username` and releases the rows it wrote when a reservation fails.
- **Login.** The legacy `sso` cookie is no longer set (`auth.ssoCookie*` settings are ignored). A login that fails after its session was written, or that loses the race to create its personal access, leaves no stray session.
- **Fixes.** An app managing a stream can rename it and its children without manage rights on the parent (a move still needs them). The `system.deactivateMfa` notice names the account, not the alias used in the path. `bin/access-scope-audit.js` no longer creates empty per-user audit files on SQLite.

## 2.0.0-rc.44

Security release: upgrade promptly, and read the MFA and API contract notes first: some change what clients send. Before restarting each core: run `node bin/check-config.js` with your override and `node bin/mail.js templates validate`; with `in-process` mail on an already seeded platform, add the new `mfa-change` template on one core (`node bin/mail.js templates set mfa-change <lang> <part> --file components/mail/templates/mfa-change/<lang>/<part>.pug`, `en` and `fr`, `subject` and `html`); update the account web app at the same time.

- **MFA, BREAKING: step-up.** `mfa.deactivate`, and `mfa.activate` over an active enrolment, need `{ password }` or `{ code }` (a current TOTP code, single use): `400` with `data.id: 'step-up-required'` when missing, `403 invalid-step-up` when wrong (counted in the MFA backoff). `services.mfa.stepUp.required: false` is a one-release opt-out. The account's address gets a notice on every MFA change (template `mfa-change`).
- **MFA, BREAKING: inactive methods.** A login of an account enrolled in a method that is not active on the server is refused (`403 mfa-method-inactive`); `services.mfa.allowLoginWhenMethodInactive` restores the former password-only login. Legacy `services.mfa.mode` deployments: set `services.mfa.methods.sms.active: true` before removing `mode`.
- **MFA, BREAKING: SMS.** `phone` in E.164 form, other enrolment keys only from `services.mfa.methods.sms.contentKeys`; `code` required in `mfa.confirm` and `mfa.verify`; provider templates substituted once and encoded per context. Server-generated codes have 6 digits (`codeLength`), live 300 s (`codeTtlSeconds`) and belong to their MFA session; send limits (`sendLimits`: 30 s per session, 5 per user per hour, 10 per number per day, `429 too-many-attempts`); one pending enrolment per user. Challenge-verify providers answering `200` with a body need `endpoints.verify.success: { jsonPath, equals }`.
- **MFA: sessions.** At most `services.mfa.sessions.maxPending` pending MFA sessions per core (`429 too-many-requests`), a fixed lifetime, an `mfaToken` valid only on its own account's path, and a login session refused once its enrolment changed. A refused login writes no session and no access.
- **Security: `streams.delete`.** Deleting a trashed stream with an app or shared access needs manage rights on its whole subtree, and rights to create events on the parent with `mergeEventsWithParent=true`.
- **Security, BREAKING: webhooks.** `webhooks.create` takes `url` and `scopes` only; URLs are http(s) without credentials; calls to loopback, private, link-local and other reserved addresses are refused unless listed in `webhooks.allowedPrivateHosts`; no redirects, a `webhooks.requestTimeoutMs` timeout (10 s), and `webhooks.test` answers one error for every failure.
- **Storage, BREAKING for SQLite deployments.** A PostgreSQL series engine with a SQLite base engine is refused at boot and by `check-config`; `storages.series.engine` defaults to `postgresql`, so a SQLite deployment sets it to `sqlite` or `influxdb`.
- **Email verification visible to apps.** An access that can read `:system:email` can ask for a read-only `verification/email` event (`verified`, `method`, `verifiedAt`) with `types: ['verification/email']`; a read without `types` is unchanged. The welcome mail carries a "verify my email" link (`VERIFY_LINK`) when the founding address is not proved; an existing `in-process` platform keeps its stored `welcome-email` until the template is updated.
- **Events.** Account events carry the time their value was set (stable `integrity`, `modifiedSince` works on them); `skip` / `limit` and class wildcards in `types` now apply to account streams.
- **Operators.** A core with hashed PII refuses to start without `platform.piiHmacKey` (and, in production, with the public development value). The template validator accepts a plain string literal (`= 'text'`). The encryption-at-rest image is also published for `linux/arm64`.
- **Fixes.** SQLite engine: workers no longer serve a user's files after another process deleted or replaced them, concurrent logins no longer create duplicate accesses, account deletion leaves no empty directory. HF series queries with out-of-range time bounds no longer fail. `bin/hfs-duration-repair.js` (re-run it if it failed), `bin/access-scope-audit.js` and `bin/hfs-author-scrub.js` (paged, covers deleted rows; re-run `--dry-run` once) are fixed.

## 2.0.0-rc.43

Security release: upgrade promptly. Some fixes need operator attention before the restart: on every core, run `node bin/check-config.js` (with your `--config`) and `node bin/mail.js templates validate`; fix any template it lists with `bin/mail.js templates set` (legacy templates using the backtick-literal form must be rewritten as plain text); on multi-core platforms, point `storages.engines.rqlite.url` at the local loopback. Read the configuration and multi-core notes below.

- **Configuration, BREAKING: the production layer carries deployment-neutral settings only.** `config/production-config.yml` (added under your override with `NODE_ENV=production` and no `--config`, as in the Docker image) no longer supplies platform values. If you relied on it, set in your own override: `auth.adminAccessKey`, `auth.filesReadTokenSecret`, `auth.trustedApps`, `auth.passwordResetPageURL` (unless password-reset mail is off), `auth.emailVerificationPageURL` (otherwise email verification stays off, with a boot warning) and `services.email` (the default is now `in-process`, which needs `services.email.smtp.host`). `bin/check-config.js` reports which base layer the server adds.
- **Security: `auth.trustedApps` is required and matched as origins.** Boot refuses a missing, empty or unparsable value. Scheme, host and port are compared, paths are ignored, and `*` is only accepted as a whole leading label (`https://*.example.com` matches its subdomains). A trailing `*` from older configs still means "any port".
- **Security: password reset.** Requests are throttled (`429 too-many-attempts` with `Retry-After`); reset links are single use, one per account, and links mailed before the upgrade must be requested again. A completed reset revokes the account's personal sessions and personal accesses (apps sign in again); a password change revokes the account's other personal sessions and pending reset links.
- **Security: logs.** Credential values are no longer written to logs: error logs keep the request body's keys only, credential keys are masked and URL redaction covers access tokens and one-time link tokens. Check the retention of logs written by earlier releases.
- **Security: access cache.** Cached accesses expire after `caching.accessMaxAgeSeconds` (new, default 60 s), and workers apply invalidations more strictly. A personal session with no account is refused. `backloop` is now a reserved username, and an invitation token admits a single registration.
- **Security: child accesses carry the creator's narrower rules.** A shared access created or widened by an app or shared access never reaches more than its creator; the creator's restrictions on the sub-streams it covers appear in the created access's `permissions`.
- **Security: single-event reads apply the `events.get` exclusions.** `events.getOne`, attachments, previews and HF series answer `403` to an app or shared token for an event it cannot list.
- **Security: CMC write protections.** App and shared tokens can no longer update events of the CMC inbox or internal streams, move events into or out of them, change a CMC event type, or create internal events outside their own responses stream (`403`, `data.id: 'cmc-protected-event-write'`). CMC content is validated on update as on create.
- **Security: MFA attempts.** `mfa.verify` and `mfa.confirm` reserve their attempt before the code is checked, so parallel attempts cannot exceed the limits; an attempt that keeps losing to concurrent ones gets `429`.
- **Security: admin key.** Compared in constant time and read only from the `Authorization` header on `DELETE /users/:username` (no `?auth=`, Bearer or Basic form); failed attempts are logged. `/reg/records` answers `404` to a missing or wrong key.
- **Security, BREAKING for some multi-core setups: multi-core hardening.** rqlite's HTTP API binds to loopback on every core (`storages.engines.rqlite.httpBindAddr` exposes it, with a boot warning); `storages.engines.rqlite.url` must be `http://127.0.0.1:<port>` unless `httpBindAddr` is set to the same address. `bootstrap.js promote-core` needs `--target-applied-index <n>` (from `bootstrap.js applied-index` on the target) or `--force`. A multi-core core without `storages.engines.rqlite.tls` logs a boot warning (a later release will refuse it). Core ids must match `[a-z0-9][a-z0-9-]*` and core URLs must be https origins; stored mail templates are validated before use (invalid ones are skipped and listed at boot).
- **Security: joining a core.** The joiner stages the bundle's files and installs them only after an accepted acknowledgement bound to its certificate fingerprint (refusals are `401 ack-refused`); `new-core` refuses an existing id unless `--replace`. Treat a delivered bundle and its passphrase as admin credentials: see SINGLE-TO-MULTIPLE.md, "If a bundle may have been exposed".
- **Operator tools.** `bin/platform-backloop-cleanup.js` (report, then `--apply`, once per platform) removes rows a former test-only registration path left; `bin/access-scope-audit.js [--user u]` reports existing accesses that reach further than their creator (read only); `bin/hfs-duration-repair.js` (`--dry-run`, then without the flag, once per core, safe to re-run) repairs HF series events written before 2.0.0-rc.40 whose `duration` held nanoseconds.
- **Fix: integrity with a fractional `duration`.** Events created or updated with a fractional `duration` now carry an `integrity` hash that verifies. Events written by earlier releases keep the failing hash until rewritten: `bin/integrity-check.js` reports them, and any `events.update` recomputes it.
- **Let's Encrypt: the contact email is optional.** `letsEncrypt.email` defaults to `null` and is no longer required when `letsEncrypt.enabled` is true.

## 2.0.0-rc.42

Docker operators: before upgrading, check that `storages.engines.sqlite.path` points at a mounted volume; the image now refuses to start otherwise.

- **Docker image: refuses a user data root on the container's own filesystem.** Inside the image, the server does not start when `storages.engines.sqlite.path` (per-user databases, attachments, SQLite audit and series) is on the container's own filesystem or on a tmpfs while an engine writes there: that data would be lost whenever the container is recreated. Set it to a mounted path (e.g. `/app/data/users` with `/app/data` mounted); `PRYV_EPHEMERAL_DATA_OK=true` lifts the check for a throwaway container. Native installs are not checked.
- **Configuration: `${PRYV_DATADIR}` / `${PRYV_LOGSDIR}` are gone from `production-config.yml`.** Nothing ever expanded them, so the documented plain-Docker and Dokku setups failed at boot unless the override restated both keys. INSTALL.md now shows the override the `/app/data` mount needs and the real order of the configuration layers.
- **Docker image: Node 24.18.1 and current Debian security updates.** The image stays below Node 24.19 (nodejs/node#65446) and no longer ships `curl` (use `node -e "fetch(…)"` for checks inside the container). Native installs should run Node 24.18.1 and hold the package so routine upgrades do not move past 24.18.
- **Install wizard.** The generated `run-pryv.sh` restarts the platform after a host reboot (`--restart unless-stopped`, `--stop-timeout 30`), and `pryv-config.yml`, which holds the generated secrets, is written readable by its owner only.

## 2.0.0-rc.41

Security release: upgrade promptly. No configuration change is needed for the security fixes; Docker operators, read the non-root note below.

- **Security: SMS MFA in `single` mode.** The pending code is shared by the API workers, and `mfa.verify` / `mfa.confirm` refuse unless that exact code is sent. TOTP and SMS `challenge-verify` setups were not concerned. A correct code is also no longer refused when the request reaches another worker.
- **Security: MFA changes need the account's own login.** `mfa.activate` and `mfa.deactivate` called with a delegated personal access (account delegation) get `403 delegation-genuine-login-required`.
- **Security: access aliases are set by the server only.** Use `randomAlias: true`; an `alias` in `accesses.create` is refused with `403`. Deleting an access releases only an alias of the same account.
- **Security: a delegated personal access does not see the owner's tokens.** In `accesses.get`, `accesses.getOne`, `accesses.update` and `accesses.checkApp`, it gets the `token` and `apiEndpoint` of itself and of the accesses it created only. An app authorised through a delegated session therefore gets its own access, removed with the delegation.
- **Security: login sessions belong to one account.** A session is reused and accepted only for the account it was opened for; a session left under a username by a former owner of that name is never handed over. Existing sessions keep working; the next login of each app opens a new one.
- **Security (deployments allowing `personalToken` in `user-account.delete`).** A personal token only deletes its own account, whatever the transport, and a logged-out or expired token cannot delete it.
- **Docker image: the server runs as a non-root user.** The container still starts as root, hands its data directories to the `node` user (uid 1000) and drops to it, keeping only the right to bind ports below 1024. No action for the documented layouts; data placed elsewhere needs `PRYV_OWNED_DIRS`, and files the server only reads must be readable by uid 1000. `PRYV_RUN_AS_ROOT=true` restores the previous behaviour. See INSTALL.md, "Container user".
- **Docker image for `linux/arm64`.** `pryvio/open-pryv.io` is published for `linux/amd64` and `linux/arm64` under the same tag.

## 2.0.0-rc.40

Security release: upgrade promptly. Before upgrading, check that `auth.adminAccessKey` and `auth.filesReadTokenSecret` are at least 16 characters; after upgrading, run `bin/hfs-author-scrub.js` once per core (see below).

- **Security: `accesses.update` only changes the updatable fields.** Only `name`, `deviceName`, `permissions`, `expireAfter`, `expires` and `clientData` can be updated, as the method always documented; any other field (`type`, `token`, `id`, `createdBy`, `alias`, …) is refused with `403 forbidden` and the access is left unchanged. A personal access is now valid only with a session opened for the same account (sessions survive a username change).
- **Security: registration ignores server-owned fields.** `POST /users` (and `/reg/user`, `/reg/users`) no longer takes `id`, `passwordHash` or `events` from its parameters. Custom account fields are unchanged.
- **Security: HF series `modifiedBy` is the writing access id.** Writing to a high-frequency series recorded the request's authorization value as the series event's `modifiedBy`; it now records the access id (with the caller id when given), like every other write. Operators: after upgrading the code and before restarting, run `node bin/hfs-author-scrub.js --dry-run`, then `--revoke` (rewrites the stored values and deletes the accesses concerned as `accesses.delete` does), then restart. With the Docker image, run it with `docker exec` in the running container, then restart it. The tool prints no credential.
- **Security: event ids.** A client-supplied event id must be exactly one of the accepted shapes (the store-prefixed form was not anchored at its end); attachment and preview paths are also checked to stay inside the account's directory.
- **Security, BREAKING for weak configurations: placeholder secrets refused at boot.** A core does not start when `auth.adminAccessKey` or `auth.filesReadTokenSecret` is a placeholder (such as `OVERRIDE ME`), or shorter than 16 characters with `NODE_ENV=production`. `bin/check-config.js` reports the same.
- **Security (hardening): previews no longer decode SVG.** A `picture/attached` event whose attachment is an SVG file gets `422 corrupted-data` from the previews route, as any format it cannot preview.
- **HF series `duration` in seconds.** Writing points set the series event's `duration` in nanoseconds; new writes now set it in seconds. Series events written by earlier releases keep the oversized duration until a repair tool in a later release.

## 2.0.0-rc.39

- **Security: image previews (CVE-2026-96889).** The image library behind event previews is updated: it bundled a `librsvg` with a memory flaw in SVG decoding that can lead to code execution, and previews detect an attachment's format from its content, so an SVG file attached to a `picture/attached` event was decoded when its preview was requested. Every earlier Docker image is affected; update promptly. No API or configuration change.
- **Security: cross-account consent, an accept is only taken through the capability.** A `consent/accept-cmc` or `consent/refuse-cmc` written to `:_cmc:inbox` with a relationship token is refused with `400`, `data.id: 'cmc-event-type-not-allowed'`. Before, a peer could open a relationship under any app scope of the requester's account, or mark one of its invites refused. Accepts and refusals reach the requester through the capability's responses stream, as every released version delivers them, so no client or peer change is needed.
- **Security: previews cache clean-up requires the admin key.** The previews worker's `clean-up-cache` routes now require `Authorization: <auth.adminAccessKey>`. The worker's port is internal and the public port never routed them.
- **Server-written event fields are applied onto the stored event.** Following 2.0.0-rc.38, the fields the server itself writes onto an existing event (CMC trigger status, consent withdrawal, invite state, delegation and email records, a series event's `duration`, an attachment added or removed) no longer overwrite a client `events.update` that lands in between.
- **Event types 1.1.3.** `consent/accept-cmc` declares `content.features`, the field the platform reads; `content.extra` is deprecated. No behaviour change.

## 2.0.0-rc.38

- **Cross-account consent: the offer's `features` decide the chat channel.** A relationship's `features` (`chat`, `systemMessaging`) are now resolved by the server from the offer; the accept may only narrow them (a `true` against an offer that turned the feature off is ignored). The resolved pair is recorded on the accept event (kept on update), on both relationship accesses and on the requester's inbox mirror. A relationship without chat gets no `chats:<counterparty-slug>` stream and no chat permission on either side, and a counterparty writing or editing a `message/chat-cmc` directly is refused with `403`, `data.id: 'cmc-chat-disabled'` (likewise alerts and acks without system messaging). Relationships accepted earlier keep their chat stream: read `features`, not the stream, to decide whether to offer chat. `consent/accept-cmc` `content.features` is validated. See [Sending chat messages](/guides/cross-account-messaging/#sending-chat-messages).
- **Cross-account consent: an account cannot accept its own invite.** An accept of an offer the accepting account made itself (an open link opened by its requester) fails with `cmc-self-accept-forbidden` before anything is provisioned. A self-relationship created earlier records its withdrawal when its access is deleted.
- **Server-written event fields survive a concurrent update.** A field the server writes on an event (a CMC dispatch status, a consent withdrawal, the owner's confirmation) is no longer lost when a client updates or trashes the same event at that moment: the client's change is applied onto the event as stored at write time. `content.status` and `content.failure` on CMC events are server-written only. Nothing changes in requests or responses.

## 2.0.0-rc.37

- **Security: trusted-proxy matching (CVE-2026-90711).** The library that matches `http.trustedProxies` is updated: before, an IPv4-mapped IPv6 entry with a short prefix (for example `::ffff:10.0.0.0/8` instead of `::ffff:10.0.0.0/104`) matched every IPv4 client, so any client could choose the address recorded for it. Lists in plain IPv4 notation, the names `loopback` / `linklocal` / `uniquelocal`, and the default were not affected. **Boot check:** a list that would trust every client (for example `::/1`) or a subnet that matches no client now refuses the boot, naming the entry; write IPv4 subnets in IPv4 notation (`10.0.0.0/8`).
- **SQLite storage engine.** A busy account file no longer blocks the server while it waits, and a data store's per-account key-value storage can remove an entry (`set(key, null)`).

## 2.0.0-rc.36

- **Breaking (security): no more `REDIRECTED` outcome for an auth request.** `POST /reg/access/{key}` refuses `status: 'REDIRECTED'` with `400 invalid-parameters` like any unknown status, no outcome post stores a `redirectUrl`, and the [poll](/reference/#poll-request) never answers `REDIRECTED`. The status let anyone holding a request key store an unvalidated URL served to the authentication page. No shipped authentication page sent it: a request stays on the core that created it, and an account on another core is served through the shared-secret hand-off. A custom page that posted it must stop.
- **Breaking (security): client addresses only from trusted proxies.** The address recorded in the audit log (`source.ip`) and the `X-Forwarded-Host` / `X-Forwarded-Proto` a DPoP proof is checked against are read from the forwarding headers only when the request comes from a proxy listed in `http.trustedProxies` (IPs, CIDRs, or `loopback` / `linklocal` / `uniquelocal`; default `loopback`). **Operator action:** a proxy on another host, or one reaching the core over a Docker bridge (Dokku's nginx arrives from `172.17.0.1`), must be added to the list, or every request is recorded with the proxy's address and DPoP proofs naming the public host are refused. nginx on the same host and a directly exposed core need nothing. The list in use is in the boot log; an entry that is not an IP, a CIDR or a known name refuses the boot. See [INSTALL, client addresses behind a proxy](https://github.com/pryv/open-pryv.io/blob/master/INSTALL.md#client-addresses-behind-a-proxy-httptrustedproxies).
- **Image previews are reachable on the public port again.** `{apiEndpoint}previews/events/{id}` (optional `.jpg` / `.jpeg`, `w` / `h`, `auth`) is now routed to the previews worker in-process ([Get event preview](/reference/#get-event-preview)); a core terminating TLS itself answered 404 before. Deployments behind nginx need the matching location, see [INSTALL, running behind nginx](https://github.com/pryv/open-pryv.io/blob/master/INSTALL.md#running--behind-nginx). Usernames `users`, `oauth2`, `previews`, `series` and `system` are reserved (existing accounts are not affected), `GET /reg/{username}/check_username` answers `reserved: true` for every name registration refuses, and request logs write `auth=***` for tokens passed in the query.
- **A cross-account revocation that did not take effect no longer reads completed.** A `consent/revoke-cmc` whose local delete fails ends `failed` (`cmc-revoke-delete-failed`) and is retried without telling the peer twice.
- **Cross-account consent: the withdrawal is recorded on the person's own record.** However a consent ends (its data grant deleted with `accesses.delete`, a `consent/revoke-cmc` written by the person, a revocation by the requester), the person's `consent/accept-cmc` event now carries `content.withdrawal = { at, by, accessId, revokeEventId? }`, as a delegation detach already did. The field is server-owned and never overwritten once set. Apps listing a person's consents should treat an accept event with `withdrawal` as ended; `@pryv/cmc` 3.18.0 does so by default. See [Revoking](/guides/cross-account-messaging/#revoking).
- **A consent invite can name its data grant.** A `cmcInvites` entry of the [auth request](/reference/#auth-request) may carry `accessName` (1 to 256 characters), echoed with the invite; the authentication page names the grant with it. An older core refuses an entry carrying it with `400 invalid-parameters`.
- **An auth request can require an account the user manages.** `actAsManagedOnly: true`, with `actAs: 'allow'` or a username, asks that the access be granted for a managed account only, never for the signed-in account; the authentication page enforces it and refuses with `reasonId: 'MANAGED_ACCOUNT_UNAVAILABLE'` when no managed account can be used. Echoed only when understood; an older core drops it. See [account delegation](/guides/account-delegation/#requiring-a-managed-account-actasmanagedonly).

## 2.0.0-rc.28

- **Hosted sites.** A platform can serve a small web app itself under a reserved name, for example the account app on `account.${DOMAIN}`: either from a static folder on each core (a root-based build, which each app-web-user-account release ships as a tarball) or as a fixed proxy to an upstream URL. In DNS mode the site gets its own subdomain and origin, covered by the platform certificate; in dnsLess mode it is served under `/<name>/` on the core's public URL (the API's own origin). The name is reserved, so no account can take it. See [FAQ infrastructure](/faq-infra/). The Pryv Lab now serves its account app at [https://account.pryv.me/](https://account.pryv.me/), and its `service/info` publishes `account` accordingly.
- **The master stops its rqlited when it exits early**, and refuses to start when another rqlited already answers on its port, instead of silently using it.

## 2.0.0-rc.27

- **Security: MFA per-account limit is a backoff, not a lockout.** After `services.mfa.attempts.backoff.freeFailures` (default 3) failed second factors, each further failure delays the next attempt, doubling up to `maxSeconds` (default 300); during a delay [verify](/reference/#verify-mfa-challenge), [confirm](/reference/#confirm-mfa-activation) and [trigger](/reference/#trigger-mfa-challenge) answer `429 too-many-attempts` with `Retry-After` and `error.data.retryAfterSeconds`. Someone who knows the password can no longer lock the real user out, and a success clears the tally. `attempts.perAccount` and `attempts.lockoutSeconds` are no longer read (boot warning). The `attempts` block is platform-wide: set the same values on every core. See [MFA](/customer-resources/mfa/#authenticator-app-totp).
- **Security: a TOTP code is consumed atomically.** The same code verified at the same moment on two sessions releases exactly one token.
- **MFA settings are checked at boot:** settings that cannot work stop the core with the key named instead of failing each request.
- **Security: the private profile keeps MFA state to the MFA methods.** [Get private profile](/reference/#get-private-profile) shows `mfa` without its secrets (`method`, `content`, TOTP parameters) and never the failed-attempt tally; [update private profile](/reference/#update-private-profile) refuses `mfa` and `mfaThrottle` (`400 invalid-operation`). An app access named `private` or `public` has no app profile (`400 invalid-operation`): such an access could previously reach the user's own profiles.
- **New accounts get the CMC reserved streams at creation**, so a fresh account's stream list already shows `:_cmc:`, `:_cmc:inbox` and `:_cmc:apps`.
- **Embedded DNS answers over TCP too, and conforms to the DNS RFCs** (authoritative flag, SOA on negative answers, REFUSED out of zone). **Operator action:** open TCP/53 inbound alongside UDP/53. See [DNS configuration](/customer-resources/dns-config/).

## 2.0.0-rc.23

- **Grant an app access for an account you control.** On platforms with [account delegation](/guides/account-delegation/), the authentication page asks, after sign-in, whom the access is for; an access granted for a controlled account is marked on the server (`accessInfo().delegation.grantedVia: 'app'`) and the [auth request](/reference/#auth-request) takes an `actAs` field (`'allow'`, `'deny'` or a username). **Breaking:** ending a delegation now also revokes the accesses granted through it. A delegate's token can no longer accept an OAuth2 consent (`403 access_denied`) or a cross-account consent (`400`, `delegation-grant-requires-owner`) on the controlled account. `GET /service/info` gains `account` (the account app's URL) and `features.delegation`.
- **Credential hand-off by one-time shared secret.** An [auth request](/reference/#auth-request) may ask for `credentialHandoff: 'shared-secret'`: the `ACCEPTED` poll then carries a one-time `handoff` key instead of the token, redeemed once on the user's core. Requests that do not ask behave as before; a core that does not support it ignores the field.
- **Security: a managed shared access no longer outlives its managing app access.** A shared access created by an expiring app access without `expireAfter` now takes the app's expiry, and one without expiry is refused once its app access has expired. **Breaking** ([update access](/reference/#methods-accesses-accesses-update)): clearing such a shared access's expiry, or giving its app an expiry while it has none, is refused (`invalid-operation`, with `offendingChildren` in the second case).
- **Security: a webhook stops firing once its access has expired** (or, for a shared access without expiry, once its managing app access has); it becomes `inactive`, and `webhooks.update` with `state: 'active'` reactivates it once the access is valid again.

## 2.0.0-rc.18 to 2.0.0-rc.22

- **An auth request can say how each permission should be presented.** The new optional `consent` object of the [auth request](/reference/#auth-request) marks permissions as required (`mandatory`), or as ones the user has to choose deliberately (`optIn`); a permission in neither list is optional and shown pre-selected, which is what every permission does today. `allowUserChoice` is what enables per-permission choice at all. The authentication page then mints only what the user kept, and the server verifies the result against the offer: a grant that does not match is refused with `invalid-consent-grant`, and a core that could not perform that check answers `consent-check-unavailable` rather than accepting it. Requests without a `consent` object behave exactly as before, and a core that does not support it ignores the object and falls back to all-or-nothing, so the echo of `consent` in the response is how an app detects support. Where consent is your lawful basis, prefer `optIn`: see the [consent guide](/guides/consent/).
- **The same `optIn` annotation is available on OAuth2 and cross-account consent offers**, beside the existing `mandatory`, with identical meaning: it decides whether the entry opens ticked, never what may be granted. See [OAuth2 authorization](/customer-resources/auth-oauth2/).

**Email verification is now general availability, and on by default.** `services.email.enabled.verifyEmail` defaults to `true`. Upgrading does not stop a working configuration from booting: a deployment that never set the key keeps booting, logs one warning per start, and leaves the feature off until `auth.emailVerificationPageURL` and a mail setup are in place. Setting the key to `true` explicitly makes the page URL required at boot, as before; setting it to `false` turns the feature off silently. "Mail is configured" is decided from configuration alone, with no SMTP probe, and the sender address is not part of that test, so a deployment that was sending mail without one keeps sending mail.

- **Email verification at sign-up (optional, off by default).** Operators can require a proved address before an account is created, with `account.emailVerification.requireAtRegistration`. The client requests a one-time code with [`POST {register}email-challenge`](/reference-system/#request-an-email-challenge), the holder pastes it back to [`POST {register}email-challenge/verify`](/reference-system/#verify-an-email-challenge), and the resulting `emailProof` is sent with [create user](/reference-system/#create-user). Addresses proved this way record `verificationMethod: 'email-code'`, a new proved value alongside `'email-link'` and `'operator'`. Admin-created accounts are never gated. The core refuses to boot when the gate is on and mail is incomplete, and a delivery failure blocks that registration rather than letting an unverified account through. The rate limits are keyed on the target address, because the endpoints are public: read the caveat in the [operator guide](/customer-resources/emails-setup/#at-registration-the-code-flow) before enabling it.
- **The multiple-emails surface leaves beta**, including [verify email address](/reference/#verify-email-address) and the `emails` operations of [update account information](/reference/#update-account-information). See the new [email verification guide](/guides/email-verification/).
- **The mailed verification link now carries `username`** as well as the token, so a landing page can address `/:username/account/verify-email` without an email lookup. Existing links keep working, and the parameters are appended with the right separator, so a page URL that already carries its own query keeps it intact.
- **Mail templates ship with the server.** `welcome-email`, `reset-password`, `verify-email` and `email-challenge`, in English and French, are seeded on first boot when no template directory is configured, so a fresh deployment can send mail without authoring a template first. Deployments that already hold templates are untouched.
- `GET /service/info` now always carries `features.emailVerification: { atRegistration, onAccount }`.

## 2.0.0-rc.17

- **Third-party sign-in (beta, off by default).** Pryv.io can act as an OpenID Connect client, letting an account holder sign in through an external identity provider the operator configures. New routes `GET /auth/sso/:provider/start` and `/callback`, plus a public `GET /auth/sso/providers` descriptor for the sign-in buttons. A first sign-in links the provider identity to an account **only** when that account has proved ownership of the provider's verified email address, so an address that was never inbox-proved cannot be taken over. The session is handed to the auth app through a one-time shared secret, so the token never appears in a redirect URL. See [third-party sign-in](/customer-resources/auth-sso/).
- **Fixed:** an OAuth2 authorization accept no longer mints an access through a consent that was refused or through an invalidated link.
- **Fixed:** when several data-grants serve one relationship, a consent revoke now reliably notifies the peer instead of reporting `peerNotified: false` ([#129](https://github.com/pryv/open-pryv.io/issues/129)).
- **Fixed:** `accesses.create` now rejects a creation stream-id with junk after a valid prefix, or longer than 100 characters, as its error message already promised ([#130](https://github.com/pryv/open-pryv.io/issues/130)).

## 2.0.0-rc.16

_(supersedes the 2.0.0-rc.15 tag, which was cut from a commit that failed CI and was never published.)_

- **MFA: per-account failed-attempt limit.** The failed-second-factor budget now also accrues per account, not only per pending MFA session, so repeated wrong codes across repeated logins no longer reset it. Once an account reaches `services.mfa.attempts.perAccount` failures within the window, the second-factor step is locked and `mfa.verify`, `mfa.confirm` and `mfa.challenge` answer `429 too-many-attempts` with a `Retry-After` header. Password login is not locked and existing tokens keep working, so a password-holder cannot use this to lock a user out. A lock clears on its own, or immediately through `mfa.recover` or the admin deactivation. New config `services.mfa.attempts`: `perSession` (5), `perAccount` (20, `0` disables), `perAccountWindowSeconds` (900), `lockoutSeconds` (900). This supersedes the known limitation noted in 2.0.0-rc.14.

## 2.0.0-rc.14

**MFA: server-side TOTP (authenticator apps), enabled by default, alongside SMS.** MFA is no longer SMS-only and is now active by default. A built-in TOTP factor (RFC 6238) works with no configuration and no external service, and is the default method; SMS keeps working unchanged and stays off until configured. Nothing is forced: a user with no enrolled factor logs in exactly as before. [`mfa.activate`](/reference/#activate-mfa) takes an optional `method` and returns an `otpauthUri` and Base32 `secret` for TOTP; `auth.login` returns `mfaMethod` next to `mfaToken`; `service.info().features.mfa.methods` lists the active methods so a client offers only what the operator enabled. Legacy deployments upgrade unchanged: a configuration carrying the old `services.mfa.mode` keeps precedence. **To keep MFA off after upgrading, set `services.mfa.active: false`.** See [MFA setup](/customer-resources/mfa/).

- **Multiple emails per account (beta).** An account can hold more than one address, each with its own verification state, while the singular `email` stays authoritative as the primary. `GET /:username/account` returns an `emails` array; `PUT /:username/account` accepts an `emails` operations object (`add`, `setPrimary`, `remove`, `resend`); `POST /:username/account/verify-email` consumes the mailed one-time token. `verificationMethod` distinguishes proved ownership (`'email-link'`, `'operator'`) from asserted (`'registration'`, `'legacy'`), so a `verified` status alone does not imply proof. Existing accounts need no migration.
- **Email verification ships OFF by default in this release (beta).** Enabling it makes `auth.emailVerificationPageURL` a required key, and a required key that is unset refuses the boot, so a default-on sub-feature could stop a previously valid deployment from starting. Opt in with both keys together. (In a later release this becomes on by default, with a soft landing instead of a boot refusal: see the entry at the top of this page.)
- **Shared secrets: hand a secret to a third party by one-time key.** Instead of putting an apiEndpoint in a URL, where it survives in history, referrer headers and access logs, store the payload on the account and hand over a random key redeemable exactly once. [Create](/reference/#create-shared-secret) returns the key once and keeps only its SHA-256; [redeem](/reference/#redeem-shared-secret) takes no token, since the key is the credential, and travels in the request body; [status](/reference/#get-shared-secret-status) inspects without consuming. An optional signature binds redemption to a passphrase or an HMAC proof. An access can be barred from minting them with the `secretSharing` feature permission. Config: `sharedSecrets.enabled` (default `true`), `maxSizeBytes`, `maxTtl`.
- **OAuth2: DPoP, sender-constrained tokens (RFC 9449, beta).** A client can bind its tokens to a key pair it holds, so a stolen bearer token alone is useless: every call must carry a short-lived `DPoP` proof. Opt-in per session and backward compatible. Proofs are single-use cluster-wide, enforcement sits in the shared access-validation path (REST, batch, socket.io and HF series alike, fail-closed), and a refresh must prove the same key. Requires a reverse proxy that overwrites `X-Forwarded-Host` / `X-Forwarded-Proto`, since proofs bind to the client-facing URI.
- **OAuth2: `private_key_jwt` client authentication (RFC 7521/7523, beta).** A confidential client can authenticate with a signed JWT instead of a shared secret, by registering its public JWK Set (ES256 only). Verification failures answer uniformly, so the endpoint leaks nothing about why.
- **OAuth2: revocation reaches live tokens cluster-wide (beta).** Revoking a client now also kills already-issued access tokens within `oauth.clientRevokeCheckSeconds` (default 30), including open socket.io connections and the HF series token cache, instead of letting them live out their TTL. Operators can also revoke by key thumbprint, which kills everything bound to that key including later refresh attempts, and inspect what a revocation would hit.
- **OAuth2: an abandoned authorization code no longer leaves its access alive.** The access minted at consent is revoked when the token exchange never succeeds. Session accesses now carry an explicit `{ feature: 'selfRevoke', setting: 'allowed' }` permission, and `accesses.create` accepts `setting: 'allowed'` as the explicit form of the default.
- **Observability rebuilt: no third-party agent.** ⚠ If you enabled the optional APM integration in an earlier version, read the note below. Telemetry is now constructed by the platform from a closed vocabulary rather than auto-instrumented by a vendor agent, and shipped over OTLP to any backend, including a collector inside your own infrastructure. What can be emitted is per-method call counts, duration histograms and error counts, labelled with an API method id, a status class and a documented error id, plus service name, version, machine hostname and worker index. Request URLs, parameters, bodies, headers, usernames, identifiers, log records and error *messages* have no representation in the schema. Error reports are aggregated and time-coarsened, because a precise failure timestamp is a re-identification handle. **Earlier versions:** the vendor agent's scrubbing configuration was placed in a file the agent does not read, so it never loaded, and affected deployments sent request URLs, the `Host` header, route parameters including the username, obfuscated SQL and forwarded log records including their message text. Assume that applied for as long as the integration was enabled and check what your provider account holds. See [observability](/customer-resources/observability/).
- **Fixed:** concurrent `streams.create` of the same id returns `409 item-already-exists` instead of a `500` leaking the storage engine's unique-constraint message ([#126](https://github.com/pryv/open-pryv.io/issues/126)).
- **Fixed:** attachment uploads are now bounded by `uploads.maxSizeMb`, which previously bounded only JSON bodies, so a deployment without a size-limiting proxy accepted attachments of any size. Oversized parts now answer `413 payload-too-large` carrying `data.limitMb`. **Operator note:** a deployment relying on unbounded uploads will receive `413` until the limit is raised ([#125](https://github.com/pryv/open-pryv.io/issues/125)).
- **Fixed:** a peer-rejected OAuth2 consent accept answers `400 invalid_grant` with the peer's machine-readable reason instead of a bare `500`.
- **Fixed:** withdrawing consent no longer blocks re-consent through the same multi-use shareable link.
- **Fixed:** the telemetry endpoint guard refused plain `http://` to a collector on a private address, which is the layout it recommends; loopback, private and link-local destinations are now accepted and anything routable still requires `https:`. The rule moved into the emitter, so it holds however the endpoint was configured ([#119](https://github.com/pryv/open-pryv.io/issues/119)).
- **Fixed:** `451 unavailable-method` no longer blames the commercial licence when a method is unavailable for another reason, such as an operator turning an optional feature off.
- **Fixed:** a cross-account back-channel handshake could be dropped silently and permanently, leaving every later consent revocation on that relationship undeliverable. Affects 2.0.0-rc.10 and rc.11. Relationships already affected do not heal on upgrade: each needs a fresh request and accept.
- **Fixed:** two concurrent relationships with the same counterparty under the same app are now told apart, keyed on their per-request scope stream. Previously the newer relationship's back-channel overwrote the older one's pointers and deliveries were misrouted.

## 2.0.0-rc.11

- **OAuth2: refresh-token reuse detection.** Replaying an already-rotated refresh token, the signature of a stolen token chain, now revokes the whole chain rather than merely rejecting the call: the durable consent record and all live session accesses for that user and client, plus their descendants, are soft-deleted and dependent webhooks cascaded. A benign double-submit inside `oauth.refreshReuseGraceSeconds` (default 10s) is tolerated. The error response is identical whether reuse was detected or not, so the endpoint cannot be used as an oracle.
- **`oauth.*` events reach the audit trail.** Five user-scoped events, including the new `oauth.token.reuse_detected`, persist to the user's audit storage and are readable through the usual `:_audit:*` streams; four user-less events go to syslog only. Audit emission never fails a token grant.
- **Fixed:** audit input validation could never reject anything, because the validators return a diagnostic string on failure and the guard treated it as success.
- **Correction to the documentation:** cross-account consent revocation was described as a server-orchestrated dual delete in which the peer's side tears itself down. That was never implemented. A revoke tears down only the accesses on the account where it was written, and the forwarded notification is delivered without running a teardown on the receiving side, so **revocation is advisory in the trigger-writer to peer direction**. Integrators should delete their own half when they observe a revoke arriving. The enforcing direction is the local one: an accepter revoking destroys the data-grant on their own account, which is what cuts the requester's read.

## 2.0.0-rc.10

- **Cross-account consent: revocation reaches the counterparty whatever path performs it.** Deleting a relationship access with a plain `accesses.delete`, for example from a generic "connected apps" screen, now delivers the same revoke notification as the dedicated helpers, so consent withdrawal is observable on the other side regardless of how it was performed. The forwarded event always carries `content.accessId`, which is also the authoritative selector of the relationship to revoke: with several relationships to one counterparty, the previous matching could tear down the wrong one ([#109](https://github.com/pryv/open-pryv.io/issues/109)).
- **The `:_cmc:*` namespace now materialises on reads too.** An account's reserved streams are created on first use, but the trigger covered writes only, so a consumer whose first action was a read, typically an inbox watcher, got `unknown-referenced-resource` on every poll and could never bootstrap ([#111](https://github.com/pryv/open-pryv.io/issues/111)).
- **Scope edits made with a plain `accesses.update` now reach the counterparty**, like the helper flow does. The notification previously targeted a stream that only admits lifecycle events and was silently rejected there.

## 2.0.0-rc.9

- **Cross-account consent: request a delegable data-grant.** A consent request may carry `request.accessType: "app"` (default `"shared"`), so the accepted data-grant is minted as an `app` access and the approved requester can create scoped, individually-named sub-accesses within it: least-privilege re-delegation with per-actor audit attribution. Existing offers and the OAuth2 flow are unchanged.

## 2.0.0-rc.8

- **Fixed: 2.0.0-rc.7 is dead on arrival, use rc.8.** A production image built with `--omit=dev` pruned a package the OAuth2 route required at module load, so every API worker crash-looped and the core never served ([#106](https://github.com/pryv/open-pryv.io/issues/106)).

## 2.0.0-rc.7

- **OAuth2 authorization-code flow (server-side).** Pryv.io can act as an OAuth2 authorization server (RFC 6749 with PKCE), so third-party applications obtain tokens through the standard redirect flow instead of the Pryv-native access-request polling flow. Both flows remain supported. New endpoints: `GET /.well-known/oauth-authorization-server` (RFC 8414 discovery), `GET /oauth2/authorize` and `POST /oauth2/token` (authorization code, refresh, client credentials). The token response carries a Pryv `apiEndpoint` extension so multi-core clients build a working connection, and a vanilla client that calls the wrong core receives `421` with the correct `coreUrl`. Clients are registered out of band by the operator. **Consent scopes are granular, with no coarse wildcards:** the `scope` parameter carries exactly one consent-offer reference, the consent screen lets the user untick individual permissions, and the minted access carries exactly the kept subset. Revoking the durable consent record invalidates the refresh chain; narrowing it propagates on the next refresh, while widening always requires a fresh authorization. See [OAuth2](/customer-resources/auth-oauth2/).

## 2.0.0-rc.6

- **Access aliases: de-identifying endpoints.** `accesses.create` accepts `randomAlias: true`, which issues a platform-unique routable alias that replaces the username everywhere the access is addressed, including the returned `apiEndpoint` and `access-info`. Accesses handed to different parties therefore cannot be cross-matched back to one account. The alias routes exactly like the username, across cores, and is released when the access is deleted.
- **Changeable username.** [`POST /account/change-username`](/reference/#change-username) lets a user choose a new one. Accesses issued under the previous username keep working, since the old name is kept as a routable alias, and their `access-info` reports the new username. The number of changes is capped by the operator (default 2); [`GET /account/username-changes`](/reference/#username-changes) reports used, limit and remaining.
- **Fixed:** accepting a cross-account invite with an access name already in use failed permanently with a raw database duplicate-key message, and an internal retry loop kept re-attempting an accept that could never succeed ([#105](https://github.com/pryv/open-pryv.io/issues/105)).
- **Fixed:** a failed transactional email no longer returns a `500` carrying the mail-service URL and the upstream error to unauthenticated callers of password reset. The diagnostic is logged server-side instead ([#104](https://github.com/pryv/open-pryv.io/issues/104)).

## 2.0.0-rc.5

- **BREAKING: cross-account consent writes that mint or widen accesses now require a personal token.** Writing an accept or a scope-update trigger mints or widens a data-grant on the user's account, so it now requires user presence at the moment the action is recorded, closing a path where an app token with narrow write permission could trigger creation of a much broader access. Non-personal tokens receive `400 invalid-operation` with `error.data.id = "cmc-accept-requires-personal-token"`. **Revoke is gated differently**, on the standard access-permission check rather than the token class, because a revoke is a contraction: a personal token always may, the relationship's own holder may self-revoke by default, the app that created the access may, and everything else is refused with `cmc-revoke-forbidden`. Cross-platform protocol deliveries pass through unaffected. Other trigger types, including request, refuse, invalidate-link and the chat and notification families, are unchanged.
- **Optional encryption-at-rest image variant.** A published variant adds optional encryption at rest for the data directories (events, attachments, series, audit, platform database), with pluggable backends and key providers. The base image is unchanged and the variant is off until opted in.
- **`/service/info` can advertise adapters:** an optional `adapters` array of base URLs, each serving an adapter UI and a `manifest.json` describing its name, type, version and capabilities. Fully additive.

## 2.0.0-rc.4

- **Multi-core: cores join as non-voters by default**, so adding a core can no longer take an existing core's control plane offline.
- **On-demand encrypted backups.** The backup tool can encrypt its output, so plaintext personal data never touches the destination disk. Two key models: a recipient public key, where the backup host holds no secret that can decrypt its own output, or a passphrase. Each file is encrypted independently, so chunking, incremental runs and single-user restore keep working, and restore auto-detects an encrypted backup. Opt-in: without the flags, backups behave exactly as before. **A lost key makes the backup unrecoverable**, which is the point of the feature. See [encrypting the backup](/customer-resources/backup/#encrypting-the-backup).

## 2.0.0-rc.1

First release candidate of open-pryv.io v2.

- **Single-binary topology.** One process manages API, HF series and preview workers in one Docker image. No MongoDB, and no separate registration, MFA or mail containers: all merged into the core.
- **Two production-grade user-data engines:** PostgreSQL (default, cross-user queries through shared tables) or SQLite (per-user files, cleaner erasure semantics). Both pass the same test matrix at parity.
- **Multi-core cluster bootstrap** over mTLS-protected Raft, with DNS discovery and wildcard certificate renewal across the cluster.
- **Cross-account messaging and consent**, federated consent, chat and system notifications between two accounts.
- **Versioned accesses:** `accesses.update` is back, with composite-id versioning and audit history, `accesses.getOne` accepts `?includeHistory=true`, and socket.io emits `accessUpdated`.
- **Engine-agnostic schema migrations** and a v1 to v2 migration path.
- **An interactive install wizard** (`docker run … init`) that writes a commented configuration, a launcher and a configuration checker into the operator's chosen directory.
- **BREAKING since `2.0.0-pre`:** the `/reg/access` polling endpoint response shapes were trimmed (SDK callers on `pryv@>=3.5.0` are unaffected), and MongoDB was removed as a user-data storage engine, so MongoDB-backed deployments must export and re-import into PostgreSQL or SQLite. Both are documented in the dedicated entries further down this page.

## 2.0.0-rc.3

- **BREAKING — the deprecated `GET /audit/logs` route has been removed.** Query audit logs through the [Events API](/reference/#get-events) as described in the [Audit logs guide](/guides/audit-logs/): call `events.get` with the audit streams in the `streams` parameter (`:_audit:` for all, `:_audit:access-{access-id}` for one access, `:_audit:action-{method-id}` for one action). Returned items are standard audit events (`audit-log/pryv-api` / `audit-log/pryv-api-error`). No official SDK used the route.

Scoped real-time notifications for both notification transports — be notified only of the changes you care about, paired with lib-js `pryv@3.7.0` + `@pryv/socket.io@3.7.0` + `@pryv/monitor@3.7.0` (lockstep).

- **Webhooks** gained an optional [`scopes`](/reference/#webhook) field: a map of named scopes, each `{ kind, query }` where `kind` is `events` (default), `streams` or `accesses` and `query` is shaped like the matching read method's parameters (an [events.get](/reference/#get-events) query for `events`). A scoped webhook fires only on matching changes and its [data changes payload](/reference/#subscribe-to-changes) carries the matched **scope keys** instead of the coarse `eventsChanged` / `streamsChanged` messages. `scopes` is alterable via [webhooks.update](/reference/#update-webhook). Unfiltered webhooks are unchanged.
- **Websockets** gained `subscribe` / `unsubscribe` / `getSubscriptions` messages and a unified [`notificationsChanged`](/reference/#scoped-subscriptions-websockets) message. A connection holding at least one scope opts out of the coarse broadcasts and receives `notificationsChanged({ keys })` with the matched scope keys. Back-compatible: servers without the feature reject `subscribe`, and the SDK falls back to the coarse messages.
- **`@pryv/monitor`** transparently registers a scope derived from its `eventsGetScope` and uses `notificationsChanged` when the server supports it, falling back to coarse signals otherwise — no API change for monitor consumers.

## 2.0.0-rc.2

Diskless deployment shape for single-core dnsLess installs in full PostgreSQL mode — no persistent filesystem needed on the app host:

- `storages.platform.engine: postgresql` stores platform data (registrations index, DNS records, TLS certificates, invitation tokens, …) in PostgreSQL; no rqlited process runs. Single-core only — multi-core keeps rqlite; boot-time validation enforces the topology.
- New `s3` fileStorage engine: event attachments on any S3-compatible object store (`storages.file.engine: s3` + `storages.engines.s3.*`).
- New `bin/migrate-platform.js` moves platform data between rqlite and PostgreSQL in either direction (adopt diskless, or go multi-core later).
- New `bin/config-to-env.js` (+ `config-to-env` docker subcommand) converts a config file into an env file for pure-ENV `docker run --env-file` deployments.
- The install wizard offers the diskless options for dnsLess + postgresql runs and documents them as commented blocks otherwise; it now also generates a `config-to-env.sh` launcher.
- Account deletion erases attachments through the fileStorage engine, so S3-stored attachments are removed too.

## 2.0.0-pre.4

Cross-account Messaging & Consent (CMC) plugin: completeness and security hardening on the open-pryv.io server, paired with lib-js `pryv@3.4.0` + `@pryv/cmc@1.1.0` + `@pryv/monitor@3.4.0` + `@pryv/socket.io@3.4.0` (lockstep).

**Plugin completeness**
- **Capability TTL configurable per-invite.** `cmc.createInvite({ ..., expiresAt })` (or `content.request.expiresAt` on a raw `consent/request-cmc`) now controls the capability's lifetime. Plugin bounds the value to `[60s, 30d]` at mint time; out-of-range rejects with `cmc-capability-ttl-out-of-range`. Default unchanged at 7 days when omitted.
- **Features gating binding at send time.** `content.request.features.{chat, systemMessaging}` is enforced on BOTH sides — `cmc.sendChat` / `cmc.sendSystemAlert` against a relationship whose negotiated feature flag is `false` rejects with `cmc-chat-disabled` / `cmc-system-messaging-disabled`. Default-permit on omission (matches the offer-side default). `consent/scope-request-cmc` and `consent/scope-update-cmc` remain protocol-level and permitted regardless.
- **Doctor-side `revokeRelationship({ inviteEventId })` is now reliable.** Previously the inbox-mirror dropped `inviteEventId`; the plugin now stamps it from the capability access's `clientData.cmc.requestEventId` so the SDK's convenience lookup matches. The `{ accessId, scopeStreamId }` power-user form keeps working.
- **`requestEventId` populated on real-deploy capability accesses.** Pre-fix the mint hook ran pre-persist when `event.id` was null; new post-create hook stamps the real id after persistence. This makes the `inviteEventId` mirror work end-to-end.

**Security hardening (route-level guards)**
- **`clientData.cmc.*` forge-prevention.** `accesses.create` / `accesses.update` reject any user-supplied `clientData.cmc.*` with `cmc-clientdata-cmc-forbidden`. That namespace is plugin-owned end-to-end (role, appCode, counterparty, capability, requestEventId, features); allowing user-set values would let an app forge a counterparty role and bypass the handshake. The CMC plugin's own internal calls reach storage via `mall.accesses` directly so the handshake is unaffected.
- **Reserved-root immutability.** `streams.delete` rejects deletion of the five reserved CMC parents (`:_cmc:`, `:_cmc:inbox`, `:_cmc:apps`, `:_cmc:_internal`, `:_cmc:_internal:retries`) + `:_cmc:_internal:*` + plugin-managed `chats`/`collectors` segments with `cmc-reserved-stream-undeletable` — even from a personal token. Without this guard a `DELETE :_cmc:` would silently break every active relationship on the account. User-creatable `:_cmc:apps:<app>:<sub>` streams remain deletable.
- **`content.from` stamping extended.** `inboxWriteHook` already stamped from-field on `:_cmc:inbox` writes; the new counterparty-from stamping hook extends the same protection to per-app `chats:*` / `collectors:*` writes by counterparty-marked accesses. A peer cannot forge `content.from` on `message/chat-cmc`, `notification/alert-cmc`, `notification/ack-cmc`, `consent/scope-request-cmc`, or `consent/scope-update-cmc`.
- **`:_cmc:_internal:*` defense-in-depth filter.** New read-hooks on `events.get` (strips internal-stream ids from `params.streams`), `events.getOne` (returns 404 if event has internal streamId), and `streams.get` (prunes the internal subtree from the response tree). Today the internal subtree has no app-visible permissions so explicit queries return empty anyway; this guards against future regressions in the permission system.

**Tests / contract**
- **7 new error ids** on `cmc.errorIds` mirror the server-side additions: `CAPABILITY_TTL_OUT_OF_RANGE`, `HANDLER_MISSING_CAPABILITY_ID`, `CHAT_DISABLED`, `SYSTEM_MESSAGING_DISABLED`, `CLIENTDATA_CMC_FORBIDDEN`, `RESERVED_STREAM_UNDELETABLE`, `COUNTERPARTY_IDENTITY_MISSING`. New `[CMCXEC]` J9 catalogue-match test pins all 7 against the server strings.
- **J3–J10 wire-shape contract tests** added to `@pryv/cmc/test/cmc.test.js` (`listInvites` uses `streams` not `streamIds`, `listAcceptedRelationships` counterparty mapping precedence, `waitForAccept` `sinceTime` filter, `acceptInvite` `scopeStreamId` requirement + `dataGrantAccessId` resolution).

**Upgrade**
- `npm install pryv@3.4.0 @pryv/cmc@1.1.0` — `@pryv/monitor` + `@pryv/socket.io` follow via transitive resolution. No source-level breaking change; existing apps on `pryv@3.3.x` + `@pryv/cmc@1.0.x` keep working.
- Server deployments: `docker pull pryvio/open-pryv.io:2.0.0-pre.4` (Dokku/Docker), or `git pull origin master && npm install --ignore-scripts && npm rebuild && sudo systemctl restart pryv-master.service` (raw deploys).

## 2.0.0-pre

First v2 preview — major consolidation and new features.

**Open source**
- Open Pryv.io v2 is now fully open source under [BSD-3-Clause](https://opensource.org/license/bsd-3-clause). The former "Enterprise version" and Open Pryv.io are now the same codebase.
- Docker image published as [`pryvio/open-pryv.io`](https://hub.docker.com/r/pryvio/open-pryv.io) (was `pryvio/core` for v1). Pull `pryvio/open-pryv.io:2.0.0-pre`.

**Consolidated runtime**
- Registration, MFA, high-frequency series and previews are now served by a single binary (`bin/master.js`), replacing the previous per-service Docker images (`pryvio/core`, `pryvio/hfs`, `pryvio/preview`, `service-register`, `service-mfa`).
- Cluster mode: configurable N API workers + M HFS workers + optional previews worker under one master process.
- High-frequency series endpoints (`/{user}/events/{id}/series`, `/{user}/series/batch`) are reachable on the same public port as the rest of the API — an in-process dispatcher routes them to the HFS worker on `:4000`. Set `cluster.hfsWorkers: 1` (or more) to enable HFS; no external reverse proxy required. For high-throughput installs, front the cluster with nginx (reference vhost: [`docs/nginx-ingress-sample.conf`](https://github.com/pryv/open-pryv.io/blob/master/docs/nginx-ingress-sample.conf)). SDKs read `features.noHF` on `/service/info` to know whether HFS is served — auto-derived from `cluster.hfsWorkers`.

**Multi-factor authentication** (ported from the former Enterprise version)
- New API: `mfa.activate`, `mfa.confirm`, `mfa.challenge`, `mfa.verify`, `mfa.deactivate`, `mfa.recover`.
- When a user has MFA active, `auth.login` returns `{ mfaToken }` instead of a regular access token. Clients must follow up with `mfa.verify` (SMS code) to obtain the Pryv access token.
- Back-office `system.deactivateMfa` remains available alongside the user-facing `mfa.deactivate`.
- Disabled by default (`services.mfa.mode: disabled`) — existing deployments see no change.

**Registration merged into core** (was `service-register`)
- All `/reg/*` endpoints are now served by the main binary. No separate register service to deploy.
- Backing store is PlatformDB (rqlite) — replaces the previous redis/leveldb storage.
- Legacy routes, invitations, DNS-less registration and multi-core indirection are all preserved.

**Multi-core deployments**
- Per-user routes (`/:username/*`) enforce core affinity. Cross-core requests receive **HTTP 421 Misdirected Request** with body `{ error: { id: 'wrong-core', message, coreUrl } }` — clients must retry directly against `coreUrl`. No HTTP redirect is issued (cross-origin redirects strip `Authorization` headers, WebSockets cannot follow).
- `/reg/*` and `/system/*` remain load-balanceable.
- New `core.url` per-core config override for **DNSless multi-core** deployments where FQDNs cannot be derived from `{core.id}.{dns.domain}`. Other cores discover the URL via `Platform.coreIdToUrl()` (PlatformDB-backed).

**Storage**
- **PostgreSQL backend** (optional): full MongoDB parity for events, streams, accounts. Select via `storages.engines.*` config. **Note:** v1→v2 data migration currently only operates from a MongoDB v1 source; migration into a PostgreSQL v2 backend is not yet supported. See [INSTALL.md](https://github.com/pryv/open-pryv.io/blob/master/INSTALL.md).
- **rqlite** is now the only platform-storage engine — the legacy sqlite platform store was removed. `master.js` always spawns `rqlited`.

**Upgrading from v1**
- Toolkit at [`dev-migrate-v1-v2`](https://github.com/pryv/dev-migrate-v1-v2): exports v1 user data (MongoDB) and produces a v2-compatible backup directory that `bin/backup.js --restore` can import.

**Access versioning**
- `accesses.update` is **back** (was removed in early v2). `PUT /accesses/{id}` mutates the head, snapshots the prior state into history, and bumps the access's `serial`. Mutable fields: `name`, `deviceName`, `permissions`, `expireAfter` / `expires`, `clientData`. See [Update access](/reference/#accesses.update).
- New `GET /accesses/{id}` ([Get one access](/reference/#accesses.getOne)) accepting either bare `<base>` or composite `<base>:<serial>` ids. Composite with an older serial returns the historical snapshot + a `current` hint. Pass `?includeHistory=true` for the full version history.
- Composite-id wire format: `access.id` / `access.createdBy` / `access.modifiedBy` now serialise as `<base>:<serial>` once an access has been updated at least once. Never-updated accesses still serialise as bare cuid — fully backwards-compatible. Use [`pryv.utils.parseAccessRef`](https://github.com/pryv/lib-js/blob/master/components/pryv/src/utils.js) (lib-js ≥ 3.1.0) to extract `{ base, serial }`.
- Composite-id conflict: `accesses.update` and `accesses.delete` require the caller's `{id}` to match the current head's serial. A stale composite returns **`409 stale-resource`** with `data: { provided, currentSerial }`; refetch and retry.
- New socket.io event `accessUpdated` fired after every successful `accesses.update`, alongside the existing coarse-grained `accessesChanged`. Payload: `{ type: 'access-updated', accessId: '<base>:<serial>', serial }`.
- Chain rules: shared-access permissions must remain a subset of their managing app; narrowing a parent rejects with `offendingChildren` if any managed child would be orphaned. Expiry chain enforced on both `accesses.update` AND retrofitted on `accesses.create` (**breaking** if you previously created shared accesses with longer expiry than the parent app).

**Cross-account Messaging & Consent (CMC plugin)**
- New `:_cmc:` reserved stream-id namespace + nine `cmc/*` event types power direct cross-platform / cross-core consent + chat + system-channel flows between two Pryv.io accounts — without shared CA, federation auth, or a central registry. The peer's `apiEndpoint` (with its existing access token) is the entire auth surface.
- Per-app scoping: data lives under `:_cmc:apps:<app-code>:[<user-path>:]chats:<counterparty-slug>` and `:_cmc:apps:<app-code>:[<user-path>:]collectors:<counterparty-slug>` so an access can be scoped at app-level (`:_cmc:apps:<app>:*`) or per-request (`:_cmc:apps:<app>:<request-slug>:*`) via natural prefix matching.
- One-shot capability-URL handoff for cross-platform acceptance; bidirectional shared accesses post-acceptance.
- Server-stamped `content.from` on inbox writes (unforgeable counterparty identity).
- Auto `accesses.update` post-hook delivers `cmc/system-scope-update-v1` to the peer whenever a CMC-tagged access has its permissions changed.
- Outbound retry queue persists pending retries as events in `:_cmc:_internal:retries` with exponential backoff; no new storage primitive.
- Backwards-compat: nothing legacy changes; deployments that don't use CMC see the namespace as inert. No migration required.
- Client SDK: [`@pryv/cmc`](https://www.npmjs.com/package/@pryv/cmc) (lib-js sibling package, `npm install @pryv/cmc`) ships slug + stream-id builders, lifecycle wrappers (`createInvite`, `acceptInvite`, `sendChat`, `sendSystemAlert`, `revokeRelationship`, `waitForAccept`, `listAcceptedRelationships`, `readOffer`), and a frozen `errorIds` catalogue mirroring the server-side `CmcErrorIds`. Source: [`lib-js/components/pryv-cmc/`](https://github.com/pryv/lib-js/tree/master/components/pryv-cmc). Design docs: [`components/cmc/README.md`](https://github.com/pryv/open-pryv.io/blob/master/components/cmc/README.md), [`IMPLEMENTERS-GUIDE.md`](https://github.com/pryv/open-pryv.io/blob/master/components/cmc/IMPLEMENTERS-GUIDE.md), [`INTERNALS.md`](https://github.com/pryv/open-pryv.io/blob/master/components/cmc/INTERNALS.md).

**Fixes**
- **Password-reset email** (2.0.0-pre.3): the `account.requestPasswordReset` mail now reliably embeds the platform's password-reset URL even when that config value is populated by an override or extra-config plugin. Previously, in some boot orderings the captured config slice missed the value and the Pug template rendered a relative `?resetToken=…` href that Outlook/Apple Mail QuickLook silently dropped. New template substitution `#{RESET_LINK}` provides the pre-composed full URL — existing templates using `#{RESET_URL}?resetToken=#{RESET_TOKEN}` keep working unchanged.

**Known gaps in 2.0.0-pre**
- **OAuth2 authorization-code flow** (RFC 6749 `/oauth2/authorize`, `/oauth2/token`, client registration, refresh tokens, PKCE) is **not** in this preview. Clients that need OAuth2-style authorization must continue using the existing `/reg/access` polling flow (now core-affinity aware in multi-core deployments).

### 1.9.3
- Added Audit from Entreprise version to Open-Pryv.io.

### 1.9.2
- Refactored Attachments (Event Files) Logic to be modular for future cloud storage of files such as S3.

### 1.9.1
- Implemented ferretDB compatibility allowing full-open source modules
- Replaced rec.la by backloop.dev

## 1.9.0

Many under-the-hood changes and a couple fixes, including:

- Stream response to `streams.delete` method to avoid potential timeout
- Deleted stream ids are now already reusable when following the auth process
- Username is not available anymore form `username` system stream. It should be retreived from `access-info`.

## 1.8.1

Fixes migration issue when upgrading from `1.6.x` to `1.8.0`

## 1.8.0

New features:

- Password policy support: rules for password complexity (length, character categories), age (minimum, maximum i.e. expiration) and reuse (i.e. history) can be enabled in the platform settings under 'Advanced API settings'
- External data stores support (a.k.a. dynamic mapping, or personal data mapping); enterprise users please contact us for the details.

## 1.7.14

- Fixes two issues with `selfRevoke` permissions, one of which related to the system streams backward compatibility flag; the issues caused a crash and prevented creation of accesses with `selfRevoke` permissions.

## 1.7.13

- Fixes for miscellaneous issues, including issues with the system streams backward compatibility flag (`BACKWARD_COMPATIBILITY_SYSTEM_STREAMS_PREFIX`), occasionally sluggish performance when querying events by type, and an occasional failure to restart services after a configuration change.

## 1.7.10

- API change: Don't coerce the event content values according to type
- Fixes: Allow event types validation for array

## 1.7.9

- Security fix: make password reset token single-use

## 1.7.0

Changes:

- Audit has been re-implemented, offering improved performance:
  - See the [Audit logs guide](/guides/audit-logs/) for API usage
  - Audit logs are now available through the [Events API](/reference/#get-events), deprecating the previous `GET /audit/logs` route and its data structure
- System streams have been modified. Their prefix changes from `.` (dot) to `:_system:` & `:system:`. See the [System streams page](/customer-resources/system-streams/) for details.
- Tags have been removed from Events. In Pryv.io platforms that contained them, they are migrated to streams, See `BACKWARD_COMPATIBILITY_TAGS` platform parameter in your platform configuration. The tags functionality is ensured by [Streams queries](/reference/#streams-query) for the [events.get](/reference/#get-events) API method.
- Permission levels are computed differently: If a child stream has a different permission than a parent, its level is indeed applied on the child (instead of the higher permission taking precendence as was done before).
- [Integrity hash](/reference/#data-structure-integrity) is computed for [Events, Attachments](/reference/#event) and [Accesses](/reference/#access). This functionality can be disabled.
- Automated platform migration using the [migrations.get](/reference-admin/#retrieve-platform-migrations) and [migrations.apply](/reference-admin/#apply-configuration-migrations) API methods.


## 1.6.20

New routes:

- [Deactivate MFA](/reference-admin/#deactivate-mfa-for-user) for admin API, for when the user has lost his 2nd factor.


## 1.6.19

New routes:

- [Get core](/reference-system/#get-core) API method that returns the hostname of the core on which a certain user data is stored.


## 1.6.7

New Features:

- [Streams query](/reference/#streams-query) for [events.get API method](/reference/#get-events)

Removals:

- Deprecated "GET /who-am-i" API method removed
- Remove pryvuser-cli, as it is now available through the [admin API](/reference-admin/)


## 1.6.2

Changes:

- Custom auth function has now access to all request headers. See [custom authentication guide](/guides/custom-auth/).


## 1.6.1

Changes:

- increase JSON input payload to 10MB for HF server. See [Data format](/reference/#data-format).


## v1.6.0

New features:

- System streams:
  - Customizable unique and indexed properties for registration
  - Account data accessible through Events API
  - More details on [System streams](/customer-resources/system-streams/)
- Admin API:
  - Edit platform parameters
  - Manage platform users
  - More details on [Admin reference](/reference-admin/)
- Admin Panel:
  - Web application for entreprise Pryv.io platform administration

Changes:

- New registration flow, more details on [Account creation](/reference-system/#account-creation)

Deprecated:

- Old registration flow


## v1.5.22

Changes:

- Deleting an app token deletes the shared accesses that were generated from it (if any).


## v1.5.18

New Features:

- Call 'GET /access-info' now returns the username to avoid having to extract it manually from `pryvApiEndpoint`.

Changes:

- Call 'POST /user' (create user) on register. The property `server` is now deprecated in favor of `apiEnpoint`.


## v1.5.8

New Features:

- Socket.io v2

Removals:

- Socket.io v0.9


## v1.5.6

Changes:

- Webhooks API routes now available for `shared` accesses.
- Socket.io interface availablel for `shared` accesses.
- Socket.io interface availablel for accesses with `create-only` permissions.


## v1.5.5

New feature:

- Access permission `{ "feature": "selfRevoke", "setting": "forbidden"}`, more details on [Access data structure](/reference/#access).


## v1.5

New Features:

- Events can now be part of multiple streamIds
- `authUrl` replaces `url` in **Auth request** in-progress response
- `pryvApiEndpoint` replaces `username` and `token` in **Auth request** accepted response
- `accesses.delete` has been extended for self revocation to `shared` and `app` accesses

Deprecated:

- `event.streamId`: replaced by `event.streamIds`
- `event.tags`: their functionality will soon be totally replaced by streamIds
- `url` in **Auth request** in-progress response
- `username` and `token` in **Auth request** accepted response

Removals:

- Timetracking functionalities have been removed
  - singleActivity streams are now standard streams
  - `events.start`
  - `events.stop`
- `accesses.update`


## V1.4

New features:
 - Auth request now accepts a custom `serviceInfo` object, which is returned by the polling url. In case of success, a `pryvApiEndpoint` field is returned. See [Auth request](/reference/#auth-request) for more details.
 - Add `create-only` permission level. See the [Access data structure](/reference/#access) for more details.
 - Add multi-factor authentication for login using the optional MFA service. See the [MFA API methods](/reference/#multi-factor-authentication) for more details.
 - Add auditing capabilities through the Audit API. See the [Audit API methods](/reference/#audit) for more details.
 - Pryv.io API now supports the Basic HTTP Authorization scheme.
 - Release of webhooks to notify of data changes. See Webhook [data structure](/reference/#webhook) and [methods](/reference/#webhooks) for more details.
 - Add route `/service/info` that provides a unified way for third party services to access the necessary information related to a Pryv.io platform. See [description](/reference/#service-info) for more details.
 - Most API calls now present a `Pryv-Access-Id` response header that contains the id of the access used for the call. This is the case only when a valid authorization token has been provided during the request (even if the token is expired). See [metadata](/reference/#in-http-headers) for more details.

Changes:

 - Enrich [access-info](/reference/#get-current-access-info) result with exhaustive access properties.
 - Improve the update account API call, in particular when it applies a change of email address. It now correctly checks if the email address is not already in use before updating the account and throws consistent errors.

Deprecated:

- Timetracking functionalities
  - singleActivity streams
  - events.start
  - events.stop


## V1.3

New features:

 - High Frequency events allow storing data at high frequency and high data density. Create them by using types that start with `series:X`, where X is a normal Pryv type. The API also supports inputting data into multiple series at once, this is called a 'seriesBatch' (POST `/series/batch`).
 - Add `clientData` field to Accesses.
 - Add `httpOnly` flag to server-side cookie sent in response to successful `/auth/login` request.
 - Deleted accesses can now be retrieved. See [accesses.get method](/reference/#get-accesses) for more details.
 - Accesses can now be made to expire. See the [access data structure documentation](/reference/#access) for more details.

Changes:

 - Some invalid requests that used to return a HTTP status code of 401 (Unauthorized) now return a 403 (Forbidden). Only the requests that are missing some form of authentication will return a 401 code.
 - `updates.ignoreProtectedFields` is now off by default. This means that updates that address protected fields will result in an error being returned.


## v1.2

Changes:

 - Fix login with Firefox (and other browsers using Referer but no Origin).
 - Security fix 2018020801: 'accesses.update' was missing an authorisation check.
 - Update of the API version in API responses.
 - Fix events.get JSON formatting.
 - Add configuration options to disable resetPassword and welcome emails.
 - Add configuration option to ignore updates of read-only fields.
 - Tags have a maximum length of 500 characters. An error is returned from the API when this limit is exceeded.


## v1.1.8

Changes:

- Fix edge-case behaviour on very large `streams.delete` operations.
- Direct `events.get` API call now supports really large results. Changes made have improved this call's performance by around 30%. As a by-product of this change, we now do not send the 'Content-Size' HTTP header anymore.
- Allow custom cuid-like ids when creating events.


## v1.1

New feature:

- Versioning:
  - a new endpoint on `/events/{id}` allows to retrieve a specific event by his `id`. Setting the
  `includeHistory` parameter to `true`, the response will contain an array of the previous versions
   of the event in the `history` field.


## v1.0

Validated initial set of API features.


## v0.8

Changes:

- Deletion methods now:
    - Reply to permanent deletions with a `{item}Deletion` field confirming the deleted item's identifier.
    - Always return code 200 on HTTP (that's a rollback of the v0.7.x change which was a bit too zealous to be practical).

New features:

- Event and stream deletions are now kept for sync purposes; they're accessible via parameter `includeDeletions` (`events.get`) or `includeDeletionsSince` (`streams.get`). Deletions are cleaned up after some time (currently a year).


## v0.7

Major changes here towards more standardization and flexibility:

- All JSON responses (both in HTTP and Socket.IO) are now structured as follows:
    - `{ "{resource}": {...} }` if a single resource item is expected; for example: `{ "event": {...} }`, `{ "error": {...} }`
    - `{ "{resources}": [ {...}, ... ] }` if an indeterminate number of items is expected; for example: `{ "events": [ {...}, ... ] }`
- All responses to resource creation and update calls now include the full object instead of respectively its id and nothing; for example: `{ "stream": {...} }`
- All JSON responses now include `meta.apiVersion` and `meta.serverTime` properties mirroring the original `API-Version` and `Server-Time` HTTP headers; HTTP header `API-Version` remains
- Deleting a resource now returns code 204 if the item was permanently deleted; it still returns a 200 when trashed (now including the trashed item in the response)
- Method ids for deletion/trashing are now `{resource}.delete` instead of `{resource}.del`
- The `attachments` property of events is now an array (instead of an object), with each attachment now identified by a new `id` property (instead of `fileName`)
- As a security measure, reading attached files now either requires auth via the `Authorization` HTTP header or a new `readToken` query string parameter (`auth` isn't allowed anymore in this case); the token to use is specific to each file and access, and is defined in the `readToken` property of each event attachment
- Event batch creation method has been replaced with generic batch method (`callBatch`, HTTP: `POST /`)
- Bookmarks have been renamed to "followed slices", corresponding method ids to `followedSlices.*` and HTTP routes to `/followed-slices`
- Getting events: setting the `tags` parameter now returns events with *any* of the specified tags, instead of *all* of them
- Error ids:
    - `unknown-*` errors replaced with either `unknown-resource` or `unknown-referenced-resource`
    - `item-*-already-exists` replaced with `item-already-exists`
    - `missing-parameter` replaced with `invalid-parameters-format`
- Other improvements and fixes (data validation performance, minor bugs on auth for trusted apps)

New features:

- Getting events: filter for specific event types with the `types` parameter
- Accesses can now define tag permissions in `permissions` (in addition to the existing stream permissions)
    - If only tag permissions are set, all streams are considered readable, and vice-versa
    - When stream and tag permissions conflict, the highest permission level is considered
- Full support for managing account information, including password change and reset


## v0.6

Changes to HTTP paths and auth for trusted apps:

- Get streams: removed `trashed` option for `state` as it was more trouble than anything useful
- Accesses now includes property `id` (exposed for referencing)
    - Create access response now includes both `id` and `token` properties
    - For existing accesses, `id` and `token` are equal
- Events, streams and accesses now includes change tracking properties:
    - `created` and `modified` (timestamp)
    - `createdBy` and `modifiedBy` (access id or `"system"`)
- Socket.IO method calls now directly use method ids (e.g. `events.create`  and pass method params, instead of using `command` and passing an object with method id and params
- For trusted apps only: removed the distinction between "admin" methods and others; **breaking changes**
    - `/admin/login`, `/admin/logout` and `/admin/who-am-i` moved to `/auth/login`, `/auth/logout` and `/auth/who-am-i` respectively
    - `sessionID` renamed to `token` in login response and SSO cookie data
    - *Personal* accesses are now automatically created on login; they can't be created explicitly anymore
    - `/admin/user-info` moved to `/user-info`
    - `/admin/accesses` merged into `/accesses`
    - `/admin/bookmarks` moved to `/bookmarks`
    - `/admin/profile` merged into `/profile`


## v0.5

This is a major update that will break most libs and clients, which should be updated ASAP.

- Simplified the API by removing channels and renamed folders into "streams"; adjusted the structure of accesses, streams and events accordingly; more details:
	- As a consequence, every event now belongs to a stream
	- Data migration: former channels will be converted into root-level streams, and former folders into sub-streams of those
- Events structure:
	- `event.type` is now a string of format `{class}/{format}` (e.g. `picture/attached`) instead of an object with `class` and `format` properties
	- `event.value` has been renamed to `event.content`
- Get events:
	- Renamed parameter `onlyFolders` to just `streams`
	- Added `running` boolean parameter, replacing "get running periods" method
- Removed "get running periods" (i.e. `GET /events/running`, see above)
- Removed `hidden` property of streams (ex-folders), which was mostly unused and out of place


## v0.4

- New feature: Allow HTTP method overriding by POSTing _method, _json, and _auth parameters in an URL-encoded request
- Improvement: Retrieving events for a specific timeframe now includes all events that overlap that timeframe, including period events that started earlier
- Added event type validation: the API will now check if an event being created or updated has a known type (as listed on our event types directory), and if yes perform data validation on its value (returning a 400 error if invalid)
- All error ids have been changed to use `slug-style` instead of `C_CONSTANT_STYLE` (so that e.g. `INVALID_PARAMETERS_FORMAT` is now `invalid-parameters-format`); this is consistent with the other ids we’re using in the system


## Earlier

Versions earlier than v0.4 are not covered here.
