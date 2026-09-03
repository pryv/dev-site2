---
title: API change log
description: Release notes for the Pryv.io API, tracking breaking changes, new webhook and websocket features, storage options and version-by-version updates.
---

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

Cross-account Messaging & Consent (CMC) plugin — Phase 2 + Phase 4 hardening on the open-pryv.io server, paired with lib-js `pryv@3.4.0` + `@pryv/cmc@1.1.0` + `@pryv/monitor@3.4.0` + `@pryv/socket.io@3.4.0` (lockstep).

**Plugin completeness**
- **Capability TTL configurable per-invite.** `cmc.createInvite({ ..., expiresAt })` (or `content.request.expiresAt` on a raw `consent/request-cmc`) now controls the capability's lifetime. Plugin bounds the value to `[60s, 30d]` at mint time; out-of-range rejects with `cmc-capability-ttl-out-of-range`. Default unchanged at 7 days when omitted.
- **Features gating binding at send time.** `content.request.features.{chat, systemMessaging}` is enforced on BOTH sides — `cmc.sendChat` / `cmc.sendSystemAlert` against a relationship whose negotiated feature flag is `false` rejects with `cmc-chat-disabled` / `cmc-system-messaging-disabled`. Default-permit on omission (matches the offer-side default). `consent/scope-request-cmc` and `consent/scope-update-cmc` remain protocol-level and permitted regardless.
- **Doctor-side `revokeRelationship({ inviteEventId })` is now reliable.** Previously the inbox-mirror dropped `inviteEventId`; the plugin now stamps it from the capability access's `clientData.cmc.requestEventId` so the SDK's convenience lookup matches. The `{ accessId, scopeStreamId }` power-user form keeps working.
- **`requestEventId` populated on real-deploy capability accesses.** Pre-fix the mint hook ran pre-persist when `event.id` was null; new post-create hook stamps the real id after persistence. Affects Phase 1.1 inviteEventId-mirror flow end-to-end.

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
