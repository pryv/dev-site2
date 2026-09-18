---
title: API change log
description: Release notes for the Pryv.io API, tracking breaking changes, new webhook and websocket features, storage options and version-by-version updates.
---

## Unreleased

- **Grant an app access for an account you control.** On platforms with [account delegation](/guides/account-delegation/), the authentication page asks, after sign-in, whom the access is for; an access granted for a controlled account is marked on the server (`accessInfo().delegation.grantedVia: 'app'`) and the [auth request](/reference/#auth-request) takes an `actAs` field (`'allow'`, `'deny'` or a username). **Breaking:** ending a delegation now also revokes the accesses granted through it. A delegate's token can no longer accept an OAuth2 consent (`403 access_denied`) or a cross-account consent (`400`, `delegation-grant-requires-owner`) on the controlled account. `GET /service/info` gains `account` (the account app's URL) and `features.delegation`.
- **Credential hand-off by one-time shared secret.** An [auth request](/reference/#auth-request) may ask for `credentialHandoff: 'shared-secret'`: the `ACCEPTED` poll then carries a one-time `handoff` key instead of the token, redeemed once on the user's core. Requests that do not ask behave as before; a core that does not support it ignores the field.
- **Security: a managed shared access no longer outlives its managing app access.** A shared access created by an expiring app access without `expireAfter` now takes the app's expiry, and one without expiry is refused once its app access has expired. **Breaking** ([update access](/reference/#methods-accesses-accesses-update)): clearing such a shared access's expiry, or giving its app an expiry while it has none, is refused (`invalid-operation`, with `offendingChildren` in the second case).
- **Security: a webhook stops firing once its access has expired** (or, for a shared access without expiry, once its managing app access has); it becomes `inactive`, and `webhooks.update` with `state: 'active'` reactivates it once the access is valid again.

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
