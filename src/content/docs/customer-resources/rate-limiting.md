---
title: 'Rate limiting and DoS protection'
description: Reference nginx, HAProxy, Traefik, Caddy and fail2ban configuration for rate limiting a Pryv deployment, keyed on the routes that matter, with per-workload limits and a load test to prove the limits fire.
---


This page gives operators a reference **nginx**, **HAProxy**, **Traefik** or **Caddy** setup, with **fail2ban**, that throttles abusive traffic before it reaches Pryv: per-IP limits on the unauthenticated surfaces (login, registration, password reset, access requests), per-token limits on data reads and writes, connection caps, body size limits and slow-client timeouts, plus fail2ban jails that ban the source addresses.

Every number in it is a starting point. Read the [limits at a glance](#limits-at-a-glance) table for your workload, then [verify](#verify-the-limits-fire) that the limits fire before you rely on them.


## Why at the proxy

Pryv does not limit request **rates** in-process. A per-core counter only sees its share of the traffic in a multi-core deployment, and what counts as abuse depends on the workload: a research consortium's batch import is a legitimate burst that a consumer app should never produce. The layer that sees all traffic before it is sharded, and that you already tune for your own traffic, is the reverse proxy. The full reasoning is in the compliance matrix context note on [rate limiting and DoS protection](https://github.com/pryv/compliance-matrix/blob/master/context/rate-limiting-and-dos-protection.md).

Pryv **does** bound, by itself, the checks of a credential (passwords, second factors), the actions that send mail or SMS, the few unauthenticated actions that can be keyed on an account or an address, the size of what one request may ask for, and (from 2.0.0-rc.90) how much work one account, access or connection may hold at once. These limits keep working when nothing sits in front of the core. Know them, so that your proxy limits do not duplicate or contradict them:

| In-process limit | Where it applies | Configured by | Since |
|---|---|---|---|
| Failed passwords, per account: after `freeFailures` (5) failures within `windowSeconds` (900), each further failure delays the next attempt, doubling from 2 s to 300 s; during the delay the password is not checked and the call answers `429 too-many-attempts` with `Retry-After`. A success clears the tally. | `auth/login`, `account.changePassword` (old password), the MFA step-up by password, `mfa/recover` | `auth.passwordAttempts` | 2.0.0-rc.47 |
| Failed passwords, per client address (an IPv4 address, or an IPv6 /64), whatever the account and across all cores: past `maxFailures` (30) within `windowSeconds` (900), those calls answer `429 too-many-attempts` until the window ends. Successes neither count nor clear it. | same as above | `auth.passwordAttempts.perIp` | 2.0.0-rc.47 |
| Password checks in progress, per API worker: at most `passwordCheckConcurrency` (2) password hashes and checks (and OAuth client-secret checks) at a time, with up to `passwordCheckQueue` (50) waiting at most 10 s for a turn. Beyond that the call is refused unchecked: `429 too-many-requests` with `Retry-After: 5` on the API, `503` with `error: "temporarily_unavailable"` and `Retry-After` on the OAuth endpoints. A refusal is not a failed attempt. Keep the concurrency below the thread pool size (`UV_THREADPOOL_SIZE`, 16 in the Docker image, 4 otherwise); `0` disables the limit. | `auth/login`, `account.changePassword`, `account/reset-password`, `mfa/recover`, the MFA step-up by password, registration, `POST /oauth2/token` (client secret), `/introspect`, `/revoke` | `auth.passwordCheckConcurrency`, `auth.passwordCheckQueue` | 2.0.0-rc.87 |
| Failed second factors: 5 wrong codes end the pending MFA session (`401 invalid-access-token`, the user logs in again); per account, after 3 failures each further one delays the next attempt, doubling from 2 s to 300 s, `429 too-many-attempts` with `Retry-After` | MFA `verify`, `confirm`, `challenge`, and a step-up by code | `services.mfa.attempts` (see [MFA](/customer-resources/mfa/#authenticator-app-totp)) | earlier |
| SMS sends: one every 30 s per MFA session, 5 per user per hour, 100 per core per hour (all users together), 10 per phone number per day across all cores; `429 too-many-attempts` with `retryAfterSeconds` | MFA login, `activate`, `challenge` (SMS method) | `services.mfa.methods.sms.sendLimits` (see [MFA](/customer-resources/mfa/#sms-codes-and-send-limits)) | per core, and per destination across cores: 2.0.0-rc.50 |
| Pending MFA sessions: 10 000 per core, shared by every account (`429 too-many-requests` with `Retry-After`); 5 pending login sessions per account, a further login ending the oldest | MFA login, `activate` | `services.mfa.sessions.maxPending`, `maxPendingPerUser` | per account: 2.0.0-rc.47 |
| Password reset requests: per account one a minute and five a day, per client address 20 an hour, across all cores; `429 too-many-attempts` with `Retry-After` | `account/request-password-reset` | fixed | 2.0.0-rc.43 |
| Live access requests: 10 000 per core, shared by every caller, 16 KiB each (`429 too-many-requests` with `Retry-After: 60`); 50 live requests per client address per core (`429 too-many-requests`); a request no read has opened yet lives 600 s, the first read giving it the full hour (with `access.openedOnlyByAuthPage: true`, default `false`, only the auth page's read, `GET /reg/access/{key}?authPage=1`, opens it: turn it on once your auth page sends the flag, see [Poll access request](/reference-system/#poll-access-request)) | `POST /reg/access`, `GET /reg/access/{key}` | `access.maxLiveRequests`, `access.maxRequestBytes`, `access.maxLiveRequestsPerIp`, `access.unopenedRequestTtl`, `access.openedOnlyByAuthPage` | per address, unopened life: 2.0.0-rc.47; `openedOnlyByAuthPage`: 2.0.0-rc.90 |
| Invitation token checks: 10 a minute per client address, per core; `429 too-many-attempts` with `Retry-After` | `POST /access/invitationtoken/check` | fixed | 2.0.0-rc.50 |
| External-id lookups and refused claims, together: 10 a minute per client address, per core; each lookup counts, a refused claim or replace counts, a successful one does not; `429 too-many-attempts` with `Retry-After` | `POST /reg/ext-id/cores`, `account.externalIds.claim` and `.replace` (see [External ids](/customer-resources/external-ids/#finding-the-core-that-holds-an-id)) | fixed | 2.0.0-rc.58 |
| Sign-up email codes: per **target email address**, one code a minute, 10 codes and 20 wrong tries a day | `email-challenge`, `email-challenge/verify` | `account.emailVerification.registrationCode*` (see [Emails](/customer-resources/emails-setup/#at-registration-the-code-flow)) | earlier |
| Verification mails: one every 5 minutes per email address | `account.update` (an address added, or `emails.resend`) | `account.emailVerification.resendCooldownMs` | earlier |
| Webhook test calls: one per webhook per delivery interval (5 s by default), across workers and cores; `429 too-many-attempts` | `webhooks.test` | `webhooks.minIntervalMs` | 2.0.0-rc.50 |
| Credential methods are refused inside a batch call and over socket.io (`400 invalid-operation`), so each password guess is one HTTP request your proxy sees | `auth.login`, `auth.register`, `mfa.recover`, `account.requestPasswordReset`, `account.resetPassword`, `account.verifyEmail`, `sharedSecrets.retrieve`, the email challenge methods | fixed | 2.0.0-rc.47 |
| Request size: a batch holds at most 1000 calls and returns at most 100 000 items in all (`413 too-many-results`); `events.get` `limit` / `skip` at most 100 000; a socket.io message at most 1 MB (the connection is closed past it) | batch calls, `events.get`, socket.io | `limits.batch.maxTotalItems`, `socketIO.maxMessageBytes` | 2.0.0-rc.47 |
| Request body size: JSON bodies and each file of a multipart upload; at most 10 files per upload; an image declaring more than 100 million pixels gets no preview (`413`) | every route; attachments; previews | `uploads.maxSizeMb` (default 50), `uploads.maxFiles`, `eventFiles.previewsMaxInputPixels` | file count: 2.0.0-rc.47; pixels: 2.0.0-rc.50 |
| Calls in progress, per API worker: 64 per account and 32 per access (HTTP, a batch counted once, socket.io); past either `429 too-many-requests` with `Retry-After: 1`, the call not run. Calls without an access (`auth.login`, password reset) are not counted. A streamed read counts until it has been sent. | every authenticated call | `limits.requests.maxInflightPerUser`, `limits.requests.maxInflightPerAccess` | 2.0.0-rc.90 |
| Shape of the parameters: nesting depth 64, 10 000 keys in any one object; past either `400 invalid-parameters-format` before the method runs | every call | `limits.json.maxDepth`, `limits.json.maxObjectKeys` | 2.0.0-rc.90 |
| socket.io, per API worker: 20 connections per access and 100 per account (refused at the handshake, `connect_error` with `data.id: 'too-many-requests'`), 16 calls in progress per connection (`too-many-requests`), 100 subscription scopes per connection (`invalid-operation`) | `/socket.io/` | `socketIO.maxConnectionsPerAccess`, `maxConnectionsPerUser`, `maxInflightCallsPerConnection`, `maxScopesPerConnection` | 2.0.0-rc.90 |
| Stream tree: 32 levels deep and 10 000 streams per account (trashed ones included); 100 distinct stream ids per event; past them the write answers `400` (`invalid-operation` for the tree, `invalid-parameters-format` for the ids). What an account already holds stays readable. | `streams.create`, `streams.update`, `accesses.create` / `.update` with a `defaultName`, `events.create`, `events.update` | `limits.streams.maxDepth`, `limits.streams.maxPerAccount`, `limits.events.maxStreamIds` | 2.0.0-rc.90 |
| Webhooks: 10 per access, 100 per account (`400 invalid-operation` on create), 20 scopes per webhook (`400 invalid-parameters-format`); existing webhooks keep working | `webhooks.create`, `webhooks.update` | `webhooks.maxPerAccess`, `webhooks.maxPerUser`, `webhooks.maxScopes` | 2.0.0-rc.90 |
| Streamed audit reads: one at a time per access and worker; a further read waits for its turn up to 30 s, then `429 too-many-requests` | `events.get` on `:_audit:` streams | `limits.audit.maxConcurrentReadsPerAccess`, `limits.audit.maxReadWaitMs` | 2.0.0-rc.90 |
| Idle connections: an HTTP connection with no traffic either way for 120 s is closed (a client that stopped reading no longer holds a database cursor); websockets are not affected | every HTTP route | `http.responseIdleTimeoutMs` | 2.0.0-rc.90 |
| Mail a caller can trigger: registration codes, 10 an hour per client address (`429 too-many-attempts`, `data.reason: 'ip-limit'`); verification mails, 10 distinct addresses per account a day (`emails.resend` past it: `429 too-many-attempts`, `data.reason: 'account-address-limit'`); a breaker of 500 caller-triggered mails an hour per core, counted apart for registration mails and account mails (`429 too-many-requests` where the request waits for the mail). Notices the platform sends on its own are not counted. | `email-challenge`, registration, `account.update` (`emails`), password reset | `account.emailVerification.registrationCodesPerIpPerHour`, `addressesPerAccountPerDay`, `services.email.maxPerHour` | 2.0.0-rc.90 |
| Email lookups, per core: the public ones share 30 a minute per client address (IPv4, or IPv6 /64), every lookup counted whatever the route, found or not; a signed-in account may ask about 30 addresses an hour (an address another account holds is refused with `item-already-exists`; each address asked about counts, held or not, several in one call each). Past either, `429 too-many-attempts` with `retryAfterSeconds` (`data.reason: 'account-email-lookups'` for the account one) | public: `GET /reg/{email}/check_email`, `/username`, `/uid`, `GET /reg/cores?email=`, `POST /reg/email-challenge`; account: `account.update` (`emails` added, or a changed `email`) | fixed | public: 2.0.0-rc.78; account: 2.0.0-rc.90 |
| Unknown account names, per client address (an IPv4 address or an IPv6 /64) and API worker: past 60 `/{username}/...` lookups a minute that found no account, `429 too-many-requests` for names not already cached until the minute ends; known names and other clients are not affected | every `/{username}/...` route (multi-core) | `limits.routing.unknownNamesPerClientPerMinute` | 2.0.0-rc.90 |
| Embedded DNS: at most 64 simultaneous TCP connections, size-limited UDP answers. From 2.0.0-rc.90: UDP answers that need a platform lookup (`<core>.<domain>`, `<username>.<domain>`) limited to 20 a second per client network (/24 IPv4, /56 IPv6), and, for the whole server, 100 lookups a second of names not already known that found nothing; past either the answer is dropped, every second one sent truncated so a real resolver retries over TCP. TCP is not limited by them. | the DNS server (`dns.active`) | `dns.tcpMaxConnections`, `dns.responseRateLimit.perSecond`, `slip`, `missesPerSecond` | TCP: 2.0.0-rc.46; UDP lookups: 2.0.0-rc.90 |
| Revocation lag: `oauth.clientRevokeCheckSeconds` (socket re-validation, revoked-client cache) and `caching.accessMaxAgeSeconds` (access cache) above 300 are used as 300, so a revoked or narrowed access stops working within 5 minutes where no invalidation message arrives | open sockets, every worker's access cache | as named | 2.0.0-rc.90 |

"Per core" counters are held by one core and shared by its workers; "across all cores" counters live in the platform database, so a client spreading its calls over several cores gains nothing. "Per API worker" ceilings are counted by each worker process (`cluster.apiWorkers`): a core with 4 workers lets one account hold up to 4 times the number, when its calls are spread over the workers. These ceilings bound concurrent work, not request rates, and every one of them takes `0` to turn it off. The per-address limits read the client address the way described in [how Pryv reads the client IP](#the-routes-that-matter) below: behind a proxy that is not listed in `http.trustedProxies`, every client shares the proxy's address and therefore one budget.

**The per-account delays are a soft lockout under a distributed sender.** A delay never locks the account, but whoever keeps sending wrong passwords for an account (or wrong codes, for someone who holds the password), from enough addresses to stay under the per-address budget, keeps its delay running, and the owner's own attempt during a delay is refused without being checked. A user who reports "retry in N seconds" while typing the right password is therefore a sign that someone is guessing that account; the per-IP limits and bans below are what stop it.

There is **no** in-process limit on request rates: per token, per address on data routes, on registration volume per caller, on lookups of names that exist, on OAuth2. Those are what this page covers.

Requests rejected by the proxy never reach Pryv, so they appear in the proxy's logs, not in Pryv's audit log or observability metrics. The proxy logs are therefore the record of a limit firing; keep them (see [logs are personal data](#logs-are-personal-data)).


## The routes that matter

A core serves user routes in one of two URL shapes, and the rules below match both:

- **Username in the path** (single core with `dnsLess.isActive: true`, the default, and DNSless multi-core where each core has its own `core.url`): `https://core.example.com/alice/events`.
- **Username in the host** (multi-core with embedded DNS, `dns.domain` set): `https://alice.example.com/events`. The core moves the subdomain into the path itself. Registration and access requests are then also reachable on the reserved hosts `reg.`, `access.` and `mfa.`, where the `/reg` prefix is implied (`https://reg.example.com/users`).

| Surface | Routes (path-style shown; host-style drops the `/{username}` prefix) | Caller | Key the limit on |
|---|---|---|---|
| Password login | `POST /{username}/auth/login` | unauthenticated | client IP (Pryv adds its per-account and per-address password limits) |
| MFA second factor | `POST /{username}/mfa/challenge`, `/verify`, `/confirm`, `/recover`; `/activate` and `/deactivate` (step-up by password or code) | MFA session token, personal token (`activate`, `deactivate`), or none (`recover`) | client IP (Pryv adds its per-account backoff) |
| Password reset, email verification | `POST /{username}/account/request-password-reset`, `/account/reset-password`, `/account/verify-email` | unauthenticated (the reset and verification tokens are in the body) | client IP |
| Registration | `POST /users`, `POST /reg/users`, `POST /reg/user`, `POST /reg/email-challenge`, `POST /reg/email-challenge/verify`, `POST /access/invitationtoken/check` | unauthenticated | client IP |
| Shared secrets | `POST /{username}/shared-secrets/retrieve` | unauthenticated (the secret's token is in the body) | client IP |
| Lookups | `GET /reg/{username}/check_username`, `GET /reg/{email}/check_email`, `GET /reg/{email}/username`, `GET /reg/{email}/uid`, `GET /reg/{username}/server`, `GET /reg/cores`, `GET /reg/hostings`, `GET /reg/service/info` | unauthenticated | client IP (enumeration) |
| Access requests | `POST /reg/access` (create), `GET /reg/access/{key}` (polled by the app every second while pending), `POST /reg/access/{key}` (accept or refuse) | unauthenticated | client IP, creation stricter than polling. A decision carries the request's random key (192 bits from open-pryv.io 2.0.0-rc.50, 96 before) and is posted once per request by the auth page, so the polling zone is enough for it; give decisions a zone of their own only if your logs show them abused. |
| OAuth2 | `GET /oauth2/authorize`, `POST /oauth2/authorize/accept`, `/refuse`, `POST /oauth2/token`, `/introspect`, `/revoke` | unauthenticated / client credentials | client IP |
| SSO | `GET /auth/sso/providers`, `/auth/sso/{provider}/start`, `/callback` | unauthenticated | client IP |
| Data writes | `POST /{username}/events`, `PUT`/`POST`/`DELETE /{username}/events/{id}`, `POST /{username}/streams`, `POST /{username}/accesses`, batch calls `POST /{username}/` | access token | token |
| Data reads | `GET /{username}/events`, `GET /{username}/events/{id}`, `GET /{username}/streams`, ... | access token | token |
| Attachments | upload: multipart `POST /{username}/events` or `POST /{username}/events/{id}`; download: `GET /{username}/events/{id}/{fileId}[/{fileName}]` (token or `readToken`) | access token | token, plus body size |
| High-frequency series | `POST`/`GET /{username}/events/{id}/series`, `POST /{username}/series/batch` (served by the HFS worker, port 4000) | access token | token |
| Real-time | `/socket.io/` (WebSocket) | access token in the query | concurrent connections per IP |
| Admin | `/system/...`, `/reg/admin/...` | `adminAccessKey` | client IP, with your admin and core hosts exempt |

**Pryv matches paths regardless of letter case, and with or without a trailing slash**: `/alice/auth/login`, `/alice/Auth/Login` and `/alice/auth/login/` reach the same method. Every rule that singles out a route must match the same way, or a client escapes the stricter limit with a one-character change. The configuration below uses case-insensitive locations (`~*`) ending in `/?$`, and fail2ban filters with a case-insensitive group (`(?i:...)`).

**Batch calls and socket.io.** From open-pryv.io 2.0.0-rc.47, the methods that take a password or another credential instead of an access token (`auth.login`, `mfa.recover`, password reset, registration, ...) are refused inside a batch call (`POST /{username}/`) and over socket.io, so they are only reachable through the routes above. On earlier versions, any token of an account can send many `auth.login` calls in one batch request or socket message, which none of the per-route limits below sees: upgrade before relying on them.

**How Pryv reads a token.** From the `Authorization` header (the bare token, `Bearer <token>`, or HTTP Basic with the token as user name), otherwise from the `auth` query parameter. The configuration below normalises the header the same way, so a token sent bare, as `Bearer`, with a trailing caller id, or as `?auth=` counts against one bucket. nginx cannot decode Basic credentials, so a token sent as HTTP Basic is keyed on its encoded form and gets a bucket of its own; that only matters for a client that mixes Basic with the other forms.

**How Pryv reads the client IP.** From the `X-Forwarded-For` request header only when the request comes from a proxy listed in `http.trustedProxies`, otherwise from the TCP peer, whatever header the peer sent. The header is read from the right: trusted hops are skipped and the first untrusted address is the client. `http.trustedProxies` takes IP addresses, CIDR ranges and the names `loopback`, `linklocal` and `uniquelocal`; the default `['loopback']` covers nginx on the same host and the core's own HFS dispatcher, and `[]` never reads the header. The core refuses to boot with an entry that matches no address (an IPv4-mapped IPv6 range with a prefix under 96, such as `::ffff:10.0.0.0/8`: write `10.0.0.0/8`) or a list that trusts every client, and the boot log names the list in use (`client address attribution: X-Forwarded-For trusted from [...]`). Pryv records that address as the request source in the audit log, and its per-address limits (failed passwords, password reset, access requests, invitation token checks) count it, an IPv6 address by its /64. So:

- nginx must **overwrite** the forwarding headers with what it sees: `proxy_set_header X-Forwarded-For $remote_addr;`, `X-Forwarded-Host $http_host;` and `X-Forwarded-Proto $scheme;`. Do not use `$proxy_add_x_forwarded_for`, and do not pass a client's own `X-Forwarded-Host` through: coming from a trusted proxy, it would let that client pick the host a DPoP proof is checked against.
- nginx on another host, or reaching the core over a Docker bridge (Dokku's nginx arrives from `172.17.0.1`), must be listed in `http.trustedProxies`, or every request is recorded with nginx's address and every client shares nginx's per-address budgets: 30 failed passwords from anyone, within 15 minutes, would then refuse every password check passing through that nginx until the window ends. See [INSTALL, client addresses behind a proxy](https://github.com/pryv/open-pryv.io/blob/master/INSTALL.md#client-addresses-behind-a-proxy-httptrustedproxies).
- The core's ports must not be reachable except through nginx, or clients bypass the limits. Keep `http.ip: 127.0.0.1` (the default) when nginx runs on the same host, or firewall ports 3000 and 4000 to the nginx host otherwise.
- Cores before open-pryv.io 2.0.0-rc.36 take `X-Forwarded-For` as is from any peer: there, overwriting it and closing the core's ports are the only protection of the recorded address.
- If nginx itself sits behind a load balancer or CDN, use nginx's `real_ip` module (shown below) so that `$remote_addr`, and every per-IP limit, is the real client.


## nginx configuration

Two files: the shared definitions (in the `http {}` context), and the virtual host. They assume nginx terminates TLS and Pryv listens on plain HTTP on `127.0.0.1:3000` (API) and `127.0.0.1:4000` (HFS), as in the [nginx section of INSTALL](https://github.com/pryv/open-pryv.io/blob/master/INSTALL.md#running--behind-nginx). If Pryv currently terminates TLS itself, read [composing with TLS](#composing-with-tls) first.

The values are those of the **consumer health app** profile. Requires nginx 1.17.6 or later (for `$limit_req_status`); on nginx older than 1.25.1, replace `http2 on;` with `listen 443 ssl http2;`.

### Shared definitions

```nginx
# /etc/nginx/conf.d/pryv-limits.conf  (included inside http {})

# ---------- Real client address ----------
# Only if nginx is itself behind a load balancer or CDN: list THEIR
# addresses so that $remote_addr becomes the client and every per-IP zone
# keys on the client, not on the load balancer. Leave commented otherwise.
# set_real_ip_from  10.0.0.0/8;
# real_ip_header    X-Forwarded-For;
# real_ip_recursive on;

# ---------- The access token, read the way Pryv reads it ----------
# Header first: "Bearer <t>", "Basic <b64>", or the bare token (a trailing
# " <callerId>" is ignored). Otherwise the `auth` query parameter.
# Basic is keyed on the encoded credentials (nginx cannot decode base64):
# still one bucket per token, but not the same bucket as the bare token.
map $http_authorization $pryv_auth_header {
    "~*^(?:bearer|basic)\s+(?<pryv_t1>\S+)"  $pryv_t1;
    "~^(?<pryv_t2>\S+)"                      $pryv_t2;
    default                                  "";
}
map $pryv_auth_header $pryv_token {
    ""      $arg_auth;
    default $pryv_auth_header;
}

# Split reads from writes. A zone whose key is empty does not count the
# request, so each token zone below only sees its own kind of request.
map $request_method $pryv_is_read {
    GET     1;
    HEAD    1;
    OPTIONS 1;
    default 0;
}
map $pryv_is_read $pryv_token_read  { 1 $pryv_token; default ""; }
map $pryv_is_read $pryv_token_write { 0 $pryv_token; default ""; }

# Access-request creation is a POST on the bare /reg/access path (its own
# location below); keyed on POST only so a CORS preflight is not counted.
map $request_method $pryv_ip_on_post {
    POST    $binary_remote_addr;
    default "";
}

# Hosts exempt from the admin limit: your cores (they call each other's
# /system routes) and your administration hosts. Replace the example range.
geo $pryv_admin_exempt {
    default     0;
    127.0.0.1   1;
    10.0.0.0/8  1;
}
map $pryv_admin_exempt $pryv_admin_key {
    1       "";
    default $binary_remote_addr;
}

# ---------- Zones ----------
# Size: one megabyte holds about 8 000 states on a 64-bit host, so 10m
# tracks about 80 000 client addresses at once. Token keys are longer and
# take more room, hence 20m. When a zone is full nginx evicts the least
# recently used state, so an undersized zone forgets attackers, it does not
# block legitimate users.
#
# Rate: the sustained rate; r/m for rare actions, r/s for API traffic.
# The burst each location allows on top is set where the zone is used.

# Password login and MFA: a human types a password a few times a minute.
limit_req_zone $binary_remote_addr zone=pryv_login:10m         rate=10r/m;
# Account creation, sign-up email codes, password reset: rare per person.
limit_req_zone $binary_remote_addr zone=pryv_signup:10m        rate=3r/m;
# Unauthenticated lookups (username/email checks, core discovery):
# sign-up forms check availability while the user types.
limit_req_zone $binary_remote_addr zone=pryv_lookup:10m        rate=1r/s;
# Access-request creation: one per app authorisation.
limit_req_zone $pryv_ip_on_post    zone=pryv_access_create:10m rate=6r/m;
# Access-request polling: each pending request is polled once per second,
# so 3r/s allows three people behind one address authorising at once.
limit_req_zone $binary_remote_addr zone=pryv_poll:10m          rate=3r/s;
# OAuth2, same values as the reference vhost shipped with open-pryv.io.
limit_req_zone $binary_remote_addr zone=pryv_oauth_token:10m   rate=60r/m;
limit_req_zone $binary_remote_addr zone=pryv_oauth_auth:10m    rate=300r/m;
# Admin surface: protects the admin key against guessing.
limit_req_zone $pryv_admin_key     zone=pryv_admin:1m          rate=30r/m;
# Per-token data traffic. One app instance for one user.
limit_req_zone $pryv_token_write   zone=pryv_tok_write:20m     rate=5r/s;
limit_req_zone $pryv_token_read    zone=pryv_tok_read:20m      rate=10r/s;
# High-frequency series: each request carries many points, so the request
# rate stays low even for dense sensors.
limit_req_zone $pryv_token         zone=pryv_hfs:20m           rate=5r/s;
# Per-IP backstop on everything else, including requests with no token.
limit_req_zone $binary_remote_addr zone=pryv_ip:20m            rate=20r/s;
# Concurrent connections per IP (WebSockets hold one each).
limit_conn_zone $binary_remote_addr zone=pryv_conn:10m;

# 429 is what Pryv itself uses for "slow down", and what clients retry on.
# nginx's default for both would be 503, which reads as an outage.
limit_req_status  429;
limit_conn_status 429;
# Rejections are logged at "error" (the default level): the error log at
# its default level records them, and that is what the excess-rate jail reads.

# ---------- Access log without query strings ----------
# $uri instead of $request: the query string can carry `auth=<token>`,
# which must not land in a log file. lr= is PASSED / DELAYED / REJECTED,
# or "-" when nginx answered before any limit_req ran (a 413, for instance).
log_format pryv '$remote_addr - [$time_local] "$request_method $uri $server_protocol" '
                '$status $body_bytes_sent lr=$limit_req_status rt=$request_time host=$host';
```

### Virtual host

```nginx
# /etc/nginx/sites-enabled/pryv.conf

upstream pryv_api {
    server 127.0.0.1:3000;
    keepalive 64;
}
upstream pryv_hfs {
    server 127.0.0.1:4000;
    keepalive 64;
}

server {
    listen 80;
    server_name core.example.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    http2 on;
    server_name core.example.com;

    ssl_certificate     /etc/pryv/tls/core.example.com/fullchain.pem;
    ssl_certificate_key /etc/pryv/tls/core.example.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    access_log /var/log/nginx/pryv-access.log pryv;
    error_log  /var/log/nginx/pryv-error.log;

    # ---------- Bodies and slow clients ----------
    # Pryv's uploads.maxSizeMb (default 50) caps each uploaded file and the
    # JSON body. nginx caps the WHOLE request, so allow the Pryv limit plus
    # 1 MB of multipart overhead. Lower both together if your apps never
    # upload large files. Over the limit nginx answers 413 with its own HTML
    # page. Both units are mebibytes: 51m is 53 477 376 bytes.
    client_max_body_size 51m;
    # Slow-loris protection: a client that sends nothing for this long is
    # dropped (these are idle timers between two reads, not total durations).
    client_header_timeout 15s;
    client_body_timeout   30s;
    send_timeout          60s;
    keepalive_timeout     65s;
    # nginx buffers request bodies before opening the upstream connection
    # (proxy_request_buffering on, the default): a slow upload ties up nginx,
    # not a Pryv worker. Keep it on.

    # ---------- Every location ----------
    # 30 concurrent connections per address: generous for one person's apps,
    # including a WebSocket each. Raise it where many users share one
    # address (see the hospital profile).
    limit_conn pryv_conn 30;

    # Headers Pryv needs. Inherited by every location that sets none of
    # its own; the HFS and Socket.IO locations repeat them.
    proxy_http_version 1.1;
    proxy_set_header Connection        "";
    proxy_set_header Host              $http_host;   # hosted sites and user subdomains are recognised by Host
    proxy_set_header X-Forwarded-For   $remote_addr; # overwrite, never append: Pryv records it as the client IP
    proxy_set_header X-Forwarded-Host  $http_host;   # overwrite too: a client-sent value would pick the DPoP host
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-Port  $server_port;

    # A JSON 429 shaped like Pryv's own errors, readable by browser apps.
    # Pryv's own 429s (MFA backoff, access-request ceiling, calls in
    # progress per account or access) pass through untouched:
    # proxy_intercept_errors is off.
    error_page 429 @pryv_429;
    location @pryv_429 {
        default_type application/json;
        add_header Retry-After 10 always;
        add_header Access-Control-Allow-Origin "*" always;
        add_header Access-Control-Expose-Headers "Retry-After" always;
        return 429 '{"error":{"id":"too-many-requests","message":"Rate limit reached, retry later."}}';
    }

    # Regex locations are tried in the order written; the first match wins.
    # "nodelay" serves the burst at once and rejects beyond it, instead of
    # queueing requests (which would hold connections open for attackers).
    # Pryv matches paths case-insensitively and with an optional trailing
    # slash, so every location is "~*" (case-insensitive) and ends in "/?$":
    # /alice/Auth/Login/ must not escape the login limit.

    # ---------- Password login and MFA ----------
    # 10/min sustained plus a burst of 5: a user mistyping a password a few
    # times is never refused; a guessing script gets about 10 tries a minute.
    location ~* ^(?:/[^/]+)?/(?:auth/login|mfa/(?:challenge|verify|confirm|recover|activate|deactivate))/?$ {
        limit_req zone=pryv_login burst=5 nodelay;
        proxy_pass http://pryv_api;
    }

    # ---------- Password reset and email verification ----------
    location ~* ^(?:/[^/]+)?/account/(?:request-password-reset|reset-password|verify-email)/?$ {
        limit_req zone=pryv_signup burst=3 nodelay;
        proxy_pass http://pryv_api;
    }

    # ---------- Registration, sign-up email codes, invitation tokens ----------
    location ~* ^(?:/reg)?/(?:users?|email-challenge(?:/verify)?|access/invitationtoken/check)/?$ {
        limit_req zone=pryv_signup burst=3 nodelay;
        proxy_pass http://pryv_api;
    }

    # ---------- Shared secrets ----------
    location ~* ^(?:/[^/]+)?/shared-secrets/retrieve/?$ {
        limit_req zone=pryv_lookup burst=20 nodelay;
        proxy_pass http://pryv_api;
    }

    # ---------- Access requests ----------
    # Creation (POST /reg/access, nothing after it) is held to 6/min with a
    # burst of 5 and also counts against the polling zone. Polls and
    # decisions (GET and POST /reg/access/{key}) only count against the
    # polling zone, so accepting or refusing never spends the creation budget.
    location ~* ^/reg/access/?$ {
        limit_req zone=pryv_access_create burst=5 nodelay;
        limit_req zone=pryv_poll burst=10 nodelay;
        proxy_pass http://pryv_api;
    }
    location ~* ^/reg/access/ {
        limit_req zone=pryv_poll burst=10 nodelay;
        proxy_pass http://pryv_api;
    }

    # ---------- Admin routes ----------
    location ~* ^/(?:system|reg/admin)(?:/|$) {
        limit_req zone=pryv_admin burst=20 nodelay;
        proxy_pass http://pryv_api;
    }

    # ---------- Other unauthenticated lookups ----------
    location ~* ^/reg(?:/|$) {
        limit_req zone=pryv_lookup burst=20 nodelay;
        proxy_pass http://pryv_api;
    }

    # ---------- OAuth2 and SSO ----------
    location ~* ^/oauth2/(?:token|introspect|revoke)/?$ {
        limit_req zone=pryv_oauth_token burst=10 nodelay;
        proxy_pass http://pryv_api;
    }
    location ~* ^/oauth2/authorize(?:/|$) {
        limit_req zone=pryv_oauth_auth burst=30 nodelay;
        proxy_pass http://pryv_api;
    }
    location ~* ^/auth/sso(?:/|$) {
        limit_req zone=pryv_lookup burst=20 nodelay;
        proxy_pass http://pryv_api;
    }

    # ---------- High-frequency series (HFS worker) ----------
    # Host is the worker's own address. With usernames in the host (dns.domain
    # set), the HFS worker reads the first label of Host as a username, which
    # would break these path-style requests; in DNSless mode it is harmless.
    location ~* ^/[^/]+/(?:events/[^/]+/series|series/batch)(?:/|$) {
        limit_req zone=pryv_hfs burst=20 nodelay;
        limit_req zone=pryv_ip burst=100 nodelay;
        proxy_pass http://pryv_hfs;
        proxy_http_version 1.1;
        proxy_set_header Connection        "";
        proxy_set_header Host              127.0.0.1:4000;
        proxy_set_header X-Forwarded-For   $remote_addr;
        proxy_set_header X-Forwarded-Host  $http_host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Port  $server_port;
    }

    # ---------- Real-time notifications ----------
    location /socket.io/ {
        limit_req zone=pryv_ip burst=100 nodelay;
        proxy_pass http://pryv_api;
        proxy_http_version 1.1;
        proxy_set_header Upgrade           $http_upgrade;
        proxy_set_header Connection        "upgrade";
        proxy_set_header Host              $http_host;
        proxy_set_header X-Forwarded-For   $remote_addr;
        proxy_set_header X-Forwarded-Host  $http_host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_buffering off;
    }

    # ---------- Everything else: data API, attachments, previews ----------
    # Per IP (backstop, also covers requests without a token), and per token
    # with separate read and write budgets. A batch call (POST /{username}/)
    # counts as one write however many methods it carries.
    location / {
        limit_req zone=pryv_ip        burst=100 nodelay;
        limit_req zone=pryv_tok_write burst=20  nodelay;
        limit_req zone=pryv_tok_read  burst=40  nodelay;
        proxy_pass http://pryv_api;
        # Idle time between two reads from Pryv; large event queries stream,
        # which keeps the timer fed. From 2.0.0-rc.90 the
        # core itself also closes a connection idle either way for
        # http.responseIdleTimeoutMs (120 s): keep both above your slowest call.
        proxy_read_timeout 120s;
    }
}
```

### Username-in-host deployments

With `dns.domain` set, apps address `https://alice.example.com/...` and the paths carry no username. Three additions:

1. Add the user and reserved host names to `server_name` (`server_name example.com *.example.com;`) with a wildcard certificate.
2. On `reg.`, `access.` and `mfa.` the `/reg` prefix is implied (a client may still send it), so the `/reg/...` locations above do not match the shorter form there. Give those names their own server block that reuses the same zones:

   ```nginx
   server {
       listen 443 ssl;
       http2 on;
       server_name reg.example.com access.example.com mfa.example.com;
       # same ssl_*, access_log, error_log, client_* and proxy_set_header lines as above
       location ~* ^(?:/reg)?/(?:users?|email-challenge(?:/verify)?)/?$ { limit_req zone=pryv_signup burst=3 nodelay; proxy_pass http://pryv_api; }
       location ~* ^(?:/reg)?/access/?$ {
           limit_req zone=pryv_access_create burst=5 nodelay;
           limit_req zone=pryv_poll burst=10 nodelay;
           proxy_pass http://pryv_api;
       }
       location ~* ^(?:/reg)?/access/ { limit_req zone=pryv_poll burst=10 nodelay; proxy_pass http://pryv_api; }
       location ~* ^(?:/reg)?/admin(?:/|$) { limit_req zone=pryv_admin burst=20 nodelay; proxy_pass http://pryv_api; }
       location / { limit_req zone=pryv_lookup burst=20 nodelay; proxy_pass http://pryv_api; }
   }
   ```

3. High-frequency series addressed on a user host (`/events/{id}/series`, `/series/batch`) do not match the HFS location above, which only routes the path-style form to the worker. They reach Pryv through `location /`, and the core forwards them to the HFS worker itself. To give them the HFS budget instead of the general one, add before `location /`:

   ```nginx
   location ~* ^/(?:events/[^/]+/series|series/batch)(?:/|$) {
       limit_req zone=pryv_hfs burst=20 nodelay;
       limit_req zone=pryv_ip burst=100 nodelay;
       proxy_pass http://pryv_api;   # keep Host: the username is in it
   }
   ```

### Multi-core deployments

The usual shape is one nginx per core, each with this configuration. Per-token limits stay exact: a token only works on its user's home core (other cores answer `421 wrong-core`), so all of a token's traffic meets the same nginx. The same holds for logins. Registration, lookups and access requests can be sent to any core, so a client spreading them over N cores gets N times the per-IP budget: divide those rates by the number of cores, or put a single edge in front of all cores so one counter sees everything.

**Cores in different regions.** When cores run under different data-residency or transfer rules (an EU core and a US core, say), give each region its own edge, next to its cores, rather than one edge for all of them. An edge reads every request it passes: client addresses, paths that name the account, access tokens in headers; its counters and logs keep some of them. A single edge in front of all regions therefore processes each region's personal data wherever the edge runs, which is a transfer in its own right. The same holds for a CDN: its points of presence decrypt traffic where the client happens to be, so check what the provider offers to keep decryption, logs and counters in a region before putting it in front of cores bound to one. The price of one edge per region is the one stated above: a client spreading registrations or lookups over several regions gets one budget per region. The configurations themselves may also differ per region: the limits profile, the fail2ban `ignoreip` ranges and the log retention follow each region's users and rules (see [logs are personal data](#logs-are-personal-data)).

With the embedded DNS (`dns.active`), from 2.0.0-rc.90, each core answers at most 20 UDP queries a second that need a platform lookup per client network (/24 IPv4, /56 IPv6), and at most 100 lookups a second of unknown names in all. A public resolver sending many clients' queries from one network meets the per-network limit first: it then retries the truncated answers over TCP, so size `dns.responseRateLimit.perSecond` and `dns.tcpMaxConnections` for your traffic, and watch the core log for "refused by dns.responseRateLimit". During a flood of random names, an account the DNS has not resolved in the last 30 s also falls back to TCP. Core names, an account's core, the service names and hosted sites are answered from the core list the DNS re-reads every 30 s, so a core change reaches the DNS within 30 s.

[HAProxy](#haproxy-configuration), [Traefik](#traefik-configuration) and [Caddy](#caddy-configuration) have their own configurations below. A CDN's rate-limiting rules apply the same route table with the same keys; see [Cloudflare in front](#cloudflare-in-front).


## HAProxy configuration

The same routes, keys and limits as the nginx configuration above (consumer health app profile), in one `haproxy.cfg` for HAProxy 2.8 or later. It was verified with HAProxy 3.2 in front of an open-pryv.io 2.0.0-rc.87 core in DNSless mode, with the same assumptions as for nginx: HAProxy terminates TLS, and Pryv listens on plain HTTP on `127.0.0.1:3000` (API) and `127.0.0.1:4000` (HFS), so the default `http.trustedProxies` (`['loopback']`) covers it.

What differs from nginx:

- **Windows instead of buckets.** HAProxy counts each client's requests over a sliding window (a stick table storing `http_req_rate(<window>)`) and refuses past a limit. Each limit below is the nginx rate over the window plus the nginx burst: `10r/m, burst 5` becomes "more than 15 in one minute". Refused requests are counted too, so a client that keeps sending stays refused until it slows down, where nginx lets the refill through. To use the other profiles of [limits at a glance](#limits-at-a-glance), compute each limit the same way.
- **Three counters per request.** HAProxy tracks at most three counters per request by default (`sc0` to `sc2`): connections, the per-IP budget and the budget of the route or token. Each route class needs at most those three.
- **Body size by `Content-Length`.** A request declaring more than 51 MiB is refused with `413`; a chunked body without a length is capped by Pryv only (`uploads.maxSizeMb`).
- **Token keys are hashed** (64-bit `xxh64`), so no token is kept in a table.
- **Logs go to syslog** (`/var/log/haproxy.log` on Debian and Ubuntu, through rsyslog). The log line resembles nginx's `pryv` format, without query strings, and names the limit that refused a request (`lr=REJECTED zone=pryv_login`): HAProxy has no error log of its own refusals, so the [fail2ban filters for HAProxy](#haproxy-filters) read this line.

```text
# /etc/haproxy/haproxy.cfg

global
    log /dev/log local0
    chroot /var/lib/haproxy
    user haproxy
    group haproxy
    daemon
    ssl-default-bind-options ssl-min-ver TLSv1.2
    # `echo "show table st_login" | socat stdio /run/haproxy/admin.sock`
    # lists the addresses a table holds and their counts.
    stats socket /run/haproxy/admin.sock mode 660 level admin

defaults
    mode http
    log global
    option dontlognull
    # ---------- Slow clients and idle connections ----------
    # A client must send its whole request head within 15 s (slow-loris).
    timeout http-request    15s
    timeout http-keep-alive 65s
    timeout client          60s
    timeout connect         5s
    # Idle time between two reads from Pryv; large event queries stream,
    # which keeps the timer fed. From 2.0.0-rc.90 the core
    # itself also closes a connection idle either way for
    # http.responseIdleTimeoutMs (120 s): keep both above your slowest call.
    timeout server          120s
    # WebSockets (socket.io) once upgraded.
    timeout tunnel          3600s

# ---------- Counters ----------
# One table per budget, as nginx has one zone per budget. A table counts
# requests over a sliding window (`http_req_rate(<window>)`) and a rule
# below refuses the request once the count is over the limit. The limit is
# the nginx rate over the window plus its burst: nginx's "10r/m, burst 5"
# is "more than 15 in one minute" here. Refused requests count too, so a
# client that keeps sending stays refused until it slows down.
# size: how many keys a table holds (when full, the oldest entries are
# dropped, so an undersized table forgets attackers, it does not block
# legitimate users); expire: how long an idle entry stays, at least the window.
backend st_conn
    stick-table type ipv6 size 100k expire 10m store conn_cur
backend st_login
    stick-table type ipv6 size 100k expire 10m store http_req_rate(1m)
backend st_signup
    stick-table type ipv6 size 100k expire 10m store http_req_rate(1m)
backend st_lookup
    stick-table type ipv6 size 100k expire 1m store http_req_rate(10s)
backend st_access_create
    stick-table type ipv6 size 100k expire 10m store http_req_rate(1m)
backend st_poll
    stick-table type ipv6 size 100k expire 1m store http_req_rate(10s)
backend st_oauth_token
    stick-table type ipv6 size 100k expire 10m store http_req_rate(1m)
backend st_oauth_auth
    stick-table type ipv6 size 100k expire 10m store http_req_rate(1m)
backend st_admin
    stick-table type ipv6 size 10k expire 10m store http_req_rate(1m)
backend st_ip
    stick-table type ipv6 size 200k expire 1m store http_req_rate(10s)
# Per-token tables are keyed on a 64-bit hash of the token, so no token is
# kept in a table nor shown by `show table`.
backend st_tok_write
    stick-table type integer size 200k expire 1m store http_req_rate(10s)
backend st_tok_read
    stick-table type integer size 200k expire 1m store http_req_rate(10s)
backend st_hfs
    stick-table type integer size 200k expire 1m store http_req_rate(10s)

frontend pryv
    bind :80
    bind :443 ssl crt /etc/haproxy/certs/core.example.com.pem alpn h2,http/1.1
    # Concurrent connections per address, counted when a connection opens.
    tcp-request connection track-sc0 src table st_conn
    http-request redirect scheme https code 301 unless { ssl_fc }

    # ---------- Log line without query strings ----------
    # %HPO is the path alone: the query string can carry `auth=<token>`,
    # which must not land in a log file. lr= is PASSED or REJECTED (by a
    # limit below), "-" when HAProxy answered before the limits ran; zone=
    # names the limit that refused the request. The fail2ban filters read it.
    http-request capture req.hdr(host) len 100
    log-format "%ci - [%tr] \"%HM %HPO %HV\" %ST %B lr=%[var(txn.pryv_lr)] zone=%[var(txn.pryv_zone)] rt=%Ta host=%hr"

    # ---------- Bodies ----------
    # Pryv's uploads.maxSizeMb (default 50) caps each uploaded file and the
    # JSON body. Here the whole request is capped by its Content-Length:
    # the Pryv limit plus 1 MiB of multipart overhead (51 MiB). A body sent
    # without Content-Length (chunked) is only capped by Pryv.
    http-request deny deny_status 413 if { req.hdr_val(content-length) gt 53477376 }

    # ---------- Headers Pryv needs ----------
    # Overwrite, never append: Pryv records X-Forwarded-For as the client
    # address, and a client-sent X-Forwarded-Host would pick the host a DPoP
    # proof is checked against. Host is passed as received (hosted sites and
    # user subdomains are recognised by it). Do not use `option forwardfor`,
    # which appends.
    http-request set-header X-Forwarded-For   %[src]
    http-request set-header X-Forwarded-Host  %[req.hdr(host)]
    http-request set-header X-Forwarded-Proto https if { ssl_fc }
    http-request set-header X-Forwarded-Proto http  unless { ssl_fc }
    http-request set-header X-Forwarded-Port  %[dst_port]

    # ---------- The access token, read the way Pryv reads it ----------
    # Header first: "Bearer <t>", "Basic <b64>", or the bare token (a
    # trailing " <callerId>" is ignored). Otherwise the `auth` query
    # parameter. Basic is keyed on the encoded credentials: still one bucket
    # per token, but not the same bucket as the bare token.
    http-request set-var(txn.pryv_tok) "req.fhdr(authorization),regsub('^(bearer|basic)[[:space:]]+','',i),word(1,' '),xxh64" if { req.fhdr(authorization) -m found }
    http-request set-var(txn.pryv_tok) url_param(auth),xxh64 if !{ var(txn.pryv_tok) -m found } { url_param(auth) -m found }

    # ---------- Route classes ----------
    # Pryv matches paths regardless of letter case and with or without a
    # trailing slash, so every pattern is case-insensitive (-i) and ends in
    # "/?$": /alice/Auth/Login/ must not escape the login limit. A request
    # takes the first class whose pattern matches.
    acl pryv_read      method GET HEAD OPTIONS
    acl pryv_post      method POST
    acl r_login        path -m reg -i ^(/[^/]+)?/(auth/login|mfa/(challenge|verify|confirm|recover|activate|deactivate))/?$
    acl r_reset        path -m reg -i ^(/[^/]+)?/account/(request-password-reset|reset-password|verify-email)/?$
    acl r_signup       path -m reg -i ^(/reg)?/(users?|email-challenge(/verify)?|access/invitationtoken/check)/?$
    acl r_shared       path -m reg -i ^(/[^/]+)?/shared-secrets/retrieve/?$
    acl r_access_new   path -m reg -i ^/reg/access/?$
    acl r_access       path -m reg -i ^/reg/access/
    acl r_admin        path -m reg -i ^/(system|reg/admin)(/|$)
    acl r_reg          path -m reg -i ^/reg(/|$)
    acl r_oauth_token  path -m reg -i ^/oauth2/(token|introspect|revoke)/?$
    acl r_oauth_auth   path -m reg -i ^/oauth2/authorize(/|$)
    acl r_sso          path -m reg -i ^/auth/sso(/|$)
    acl r_hfs          path -m reg -i ^/[^/]+/(events/[^/]+/series|series/batch)(/|$)
    acl r_socket       path_beg /socket.io/
    # Hosts exempt from the admin limit: your cores (they call each other's
    # /system routes) and your administration hosts. Replace the example range.
    acl admin_exempt   src 127.0.0.1 ::1 10.0.0.0/8

    http-request set-var(txn.pryv_class) str(login)        if r_login
    http-request set-var(txn.pryv_class) str(signup)       if !{ var(txn.pryv_class) -m found } r_reset
    http-request set-var(txn.pryv_class) str(signup)       if !{ var(txn.pryv_class) -m found } r_signup
    http-request set-var(txn.pryv_class) str(lookup)       if !{ var(txn.pryv_class) -m found } r_shared
    http-request set-var(txn.pryv_class) str(access_new)   if !{ var(txn.pryv_class) -m found } r_access_new
    http-request set-var(txn.pryv_class) str(access)       if !{ var(txn.pryv_class) -m found } r_access
    http-request set-var(txn.pryv_class) str(admin)        if !{ var(txn.pryv_class) -m found } r_admin
    http-request set-var(txn.pryv_class) str(lookup)       if !{ var(txn.pryv_class) -m found } r_reg
    http-request set-var(txn.pryv_class) str(oauth_token)  if !{ var(txn.pryv_class) -m found } r_oauth_token
    http-request set-var(txn.pryv_class) str(oauth_auth)   if !{ var(txn.pryv_class) -m found } r_oauth_auth
    http-request set-var(txn.pryv_class) str(lookup)       if !{ var(txn.pryv_class) -m found } r_sso
    http-request set-var(txn.pryv_class) str(hfs)          if !{ var(txn.pryv_class) -m found } r_hfs
    http-request set-var(txn.pryv_class) str(socket)       if !{ var(txn.pryv_class) -m found } r_socket
    http-request set-var(txn.pryv_class) str(data)         if !{ var(txn.pryv_class) -m found }
    acl c_login        var(txn.pryv_class) -m str login
    acl c_signup       var(txn.pryv_class) -m str signup
    acl c_lookup       var(txn.pryv_class) -m str lookup
    acl c_access_new   var(txn.pryv_class) -m str access_new
    acl c_access       var(txn.pryv_class) -m str access
    acl c_admin        var(txn.pryv_class) -m str admin
    acl c_oauth_token  var(txn.pryv_class) -m str oauth_token
    acl c_oauth_auth   var(txn.pryv_class) -m str oauth_auth
    acl c_hfs          var(txn.pryv_class) -m str hfs
    acl c_socket       var(txn.pryv_class) -m str socket
    acl c_data         var(txn.pryv_class) -m str data
    acl c_poll         var(txn.pryv_class) -m str access_new access
    acl c_per_ip       var(txn.pryv_class) -m str data hfs socket
    acl has_token      var(txn.pryv_tok) -m found

    # ---------- Counting ----------
    # Three counter slots: sc0 concurrent connections (counted when the
    # connection opens, at the top of this frontend), sc1 the per-IP budget,
    # sc2 the budget of the route class (or of the token).
    http-request track-sc2 src table st_login           if c_login
    http-request track-sc2 src table st_signup          if c_signup
    http-request track-sc2 src table st_lookup          if c_lookup
    # Creation (POST /reg/access, nothing after it) counts against its own
    # budget and the polling one; polls and decisions (GET and POST
    # /reg/access/{key}) only against the polling one, so accepting or
    # refusing never spends the creation budget. A CORS preflight is not a
    # creation.
    http-request track-sc1 src table st_poll            if c_poll
    http-request track-sc2 src table st_access_create   if c_access_new pryv_post
    http-request track-sc2 src table st_admin           if c_admin !admin_exempt
    http-request track-sc2 src table st_oauth_token     if c_oauth_token
    http-request track-sc2 src table st_oauth_auth      if c_oauth_auth
    # Per IP (backstop, also covers requests without a token), and per token
    # with separate read and write budgets. A batch call (POST /{username}/)
    # counts as one write however many methods it carries.
    http-request track-sc1 src table st_ip              if c_per_ip
    http-request track-sc2 var(txn.pryv_tok) table st_hfs       if c_hfs has_token
    http-request track-sc2 var(txn.pryv_tok) table st_tok_read  if c_data has_token pryv_read
    http-request track-sc2 var(txn.pryv_tok) table st_tok_write if c_data has_token !pryv_read

    # ---------- Limits (consumer health app profile) ----------
    # Each line: refuse past <limit> requests in the table's window.
    # 30 concurrent connections per address: generous for one person's apps,
    # including a WebSocket each.
    http-request set-var(txn.pryv_zone) str(pryv_conn)          if { sc_conn_cur(0) gt 30 }
    # Login and MFA, 10/min + 5: a user mistyping a password a few times is
    # never refused; a guessing script gets about 15 tries a minute.
    http-request set-var(txn.pryv_zone) str(pryv_login)         if c_login        { sc_http_req_rate(2) gt 15 }
    # Account creation, sign-up email codes, password reset: 3/min + 3.
    http-request set-var(txn.pryv_zone) str(pryv_signup)        if c_signup       { sc_http_req_rate(2) gt 6 }
    # Lookups, shared secrets, SSO: 1/s + 20.
    http-request set-var(txn.pryv_zone) str(pryv_lookup)        if c_lookup       { sc_http_req_rate(2) gt 30 }
    # Access-request creation 6/min + 5; polling 3/s + 10.
    http-request set-var(txn.pryv_zone) str(pryv_access_create) if c_access_new pryv_post { sc_http_req_rate(2) gt 11 }
    http-request set-var(txn.pryv_zone) str(pryv_poll)          if c_poll         { sc_http_req_rate(1) gt 40 }
    # Admin surface 30/min + 20, exempt hosts not counted.
    http-request set-var(txn.pryv_zone) str(pryv_admin)         if c_admin !admin_exempt { sc_http_req_rate(2) gt 50 }
    # OAuth2, the values of the reference nginx vhost shipped with open-pryv.io.
    http-request set-var(txn.pryv_zone) str(pryv_oauth_token)   if c_oauth_token  { sc_http_req_rate(2) gt 70 }
    http-request set-var(txn.pryv_zone) str(pryv_oauth_auth)    if c_oauth_auth   { sc_http_req_rate(2) gt 330 }
    # Per IP 20/s + 100; per token writes 5/s + 20, reads 10/s + 40, HFS 5/s + 20.
    http-request set-var(txn.pryv_zone) str(pryv_ip)            if c_per_ip       { sc_http_req_rate(1) gt 300 }
    http-request set-var(txn.pryv_zone) str(pryv_hfs)           if c_hfs has_token { sc_http_req_rate(2) gt 70 }
    http-request set-var(txn.pryv_zone) str(pryv_tok_read)      if c_data has_token pryv_read  { sc_http_req_rate(2) gt 140 }
    http-request set-var(txn.pryv_zone) str(pryv_tok_write)     if c_data has_token !pryv_read { sc_http_req_rate(2) gt 70 }

    # ---------- Refusal ----------
    # A JSON 429 shaped like Pryv's own errors, readable by browser apps.
    # 429 is what Pryv itself uses for "slow down", and what clients retry
    # on. Pryv's own 429s (MFA backoff, access-request ceiling, calls in
    # progress per account or access) pass through untouched.
    http-request set-var(txn.pryv_lr) str(PASSED)
    http-request set-var(txn.pryv_lr) str(REJECTED) if { var(txn.pryv_zone) -m found }
    http-request return status 429 content-type application/json string '{"error":{"id":"too-many-requests","message":"Rate limit reached, retry later."}}' hdr Retry-After 10 hdr Access-Control-Allow-Origin "*" hdr Access-Control-Expose-Headers Retry-After if { var(txn.pryv_zone) -m found }

    use_backend pryv_hfs if c_hfs
    default_backend pryv_api

backend pryv_api
    server api1 127.0.0.1:3000

# High-frequency series (HFS worker). Host is the worker's own address. With
# usernames in the host (dns.domain set), the HFS worker reads the first label
# of Host as a username, which would break these path-style requests; in
# DNSless mode it is harmless.
backend pryv_hfs
    http-request set-header Host 127.0.0.1:4000
    server hfs1 127.0.0.1:4000
```

Check the file with `haproxy -c -f /etc/haproxy/haproxy.cfg` and apply it with `systemctl reload haproxy`. The certificate file named by `crt` holds the certificate chain followed by the private key (`cat fullchain.pem privkey.pem`). To see what a table counts: `echo "show table st_login" | socat stdio /run/haproxy/admin.sock`.

**Username-in-host deployments.** The three changes listed for nginx apply: a wildcard certificate, the shorter paths on the reserved hosts `reg.`, `access.` and `mfa.` (match the host with `req.hdr(host)` and give those paths the same classes), and the HFS paths of a user host sent to `pryv_api` (the core forwards them to the HFS worker). This shape was not part of the verified setup.

**Multi-core deployments.** The notes for nginx hold as they are: one HAProxy per core keeps the per-token limits exact; registration, lookups and access requests spread over N cores get N times the per-IP budget, unless one edge sees all cores. HAProxy can share its tables between several HAProxy instances (`peers` section), which gives one count per client across them.


## Traefik configuration

The same routes, keys and limits as the nginx configuration above (consumer health app profile), for Traefik v3 with its file provider: a static file and a dynamic file. It was verified with Traefik 3.8 in front of an open-pryv.io 2.0.0-rc.87 core in DNSless mode, with the same assumptions as for nginx: Traefik terminates TLS, and Pryv listens on plain HTTP on `127.0.0.1:3000` (API) and `127.0.0.1:4000` (HFS), so the default `http.trustedProxies` (`['loopback']`) covers it. When Traefik reaches Pryv over a Docker network instead, Pryv sees the address of Traefik's container: list it in `http.trustedProxies` (`uniquelocal` covers the private ranges Docker uses).

What differs from nginx:

- **Counters per router.** Traefik keeps a limit's counters per router: the routes of one router share a budget, but a middleware used by two routers counts twice. The configuration below has one router per budget of the nginx configuration, so login and MFA share one budget as they do with nginx. The per-IP backstop (`pryv-ip`) and the in-flight cap (`pryv-conn`) are attached to several routers and are therefore counted per router: a client spreading its calls over the data, HFS and socket.io routers gets that many times the backstop. To keep one counter per client across routers (and across several Traefik instances), give those middlewares a `redis` block (`rateLimit.redis.endpoints`): Traefik then keys them on the middleware name and shares them.
- **The token as sent.** Traefik keys a limit on a header as it was sent and cannot read a query parameter. `Bearer <token>`, the bare token and Basic credentials are therefore three buckets for one token. A token sent as `?auth=`, or with a trailing caller id, only meets the per-IP backstop: the per-token routers only take an `Authorization` header holding one token, with or without its scheme. Your apps should send the header (lib-js does).
- **Requests in progress, not connections.** `inFlightReq` counts the requests in progress per address (a WebSocket holds one while it is open), 30 per router; an idle keep-alive connection is not counted.
- **Plain-text refusals.** Traefik answers `429` with the body `Too Many Requests` and a `Retry-After` header, without CORS headers, so a browser app sees the refusal as a network error. Traefik's `errors` middleware could serve a JSON body, but it would also replace Pryv's own 429s.
- **Body size on writes only.** The `buffering` middleware refuses a request body over 51 MiB with `413`, chunked bodies included. It holds the body before passing it on, so it is attached to the routers that take writes.
- **Whole-request read timeout.** `readTimeout` bounds the time to receive the whole request, body included: raise it if your users upload large files over slow links.
- **Logs.** The access log is JSON, the path is logged without its query string, `RouterName` names the limit's router and `OriginStatus` is `0` when Traefik refused the request itself. The [fail2ban filters for Traefik](#traefik-filters) read it.

```yaml
# /etc/traefik/traefik.yml  (static configuration)

entryPoints:
  web:
    address: ":80"
    http:
      aliasHeadersStrategy: delete
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"
    http:
      # Drop a header whose name only aliases one Traefik sets
      # (X_Forwarded_For for X-Forwarded-For).
      aliasHeadersStrategy: delete
    transport:
      respondingTimeouts:
        # The whole request, body included, must arrive within this time
        # (slow-loris protection; also the longest upload a client may take).
        readTimeout: 60s
        idleTimeout: 65s

providers:
  file:
    filename: /etc/traefik/pryv.yml
    watch: true

# ---------- Access log without query strings or headers ----------
# Only the fields below are written, and the query string is cut from the
# path: it can carry `auth=<token>`, which must not land in a log file.
# RouterName names the route class; OriginStatus is Pryv's status, 0 when
# Traefik answered itself (a limit refused the request). The fail2ban
# filters read this file.
accessLog:
  filePath: /var/log/traefik/pryv-access.log
  format: json
  fields:
    defaultMode: drop
    names:
      StartUTC: keep
      ClientHost: keep
      RequestMethod: keep
      RequestPath: keep
      RouterName: keep
      OriginStatus: keep
      DownstreamStatus: keep
      Duration: keep
    headers:
      defaultMode: drop
    queryParameters:
      defaultMode: drop

log:
  level: INFO
```

```yaml
# /etc/traefik/pryv.yml  (dynamic configuration, file provider)

http:
  services:
    pryv-api:
      loadBalancer:
        servers:
          - url: http://127.0.0.1:3000
    pryv-hfs:
      loadBalancer:
        # Host is the worker's own address (see the HFS note for nginx).
        passHostHeader: false
        servers:
          - url: http://127.0.0.1:4000

  middlewares:
    # ---------- Limits (consumer health app profile) ----------
    # Token buckets: `average` requests per `period` sustained, `burst` on top,
    # the same numbers as the nginx zones. Without `sourceCriterion` a limit
    # is keyed on the client address.
    pryv-login:
      rateLimit: { average: 10, period: 1m, burst: 5 }
    pryv-signup:
      rateLimit: { average: 3, period: 1m, burst: 3 }
    pryv-lookup:
      rateLimit: { average: 1, period: 1s, burst: 20 }
    pryv-access-create:
      rateLimit: { average: 6, period: 1m, burst: 5 }
    pryv-poll:
      rateLimit: { average: 3, period: 1s, burst: 10 }
    pryv-oauth-token:
      rateLimit: { average: 60, period: 1m, burst: 10 }
    pryv-oauth-auth:
      rateLimit: { average: 300, period: 1m, burst: 30 }
    pryv-admin:
      rateLimit: { average: 30, period: 1m, burst: 20 }
    pryv-ip:
      rateLimit: { average: 20, period: 1s, burst: 100 }
    # Per token: keyed on the Authorization header as sent.
    pryv-tok-write:
      rateLimit: { average: 5, period: 1s, burst: 20, sourceCriterion: { requestHeaderName: Authorization } }
    pryv-tok-read:
      rateLimit: { average: 10, period: 1s, burst: 40, sourceCriterion: { requestHeaderName: Authorization } }
    pryv-hfs:
      rateLimit: { average: 5, period: 1s, burst: 20, sourceCriterion: { requestHeaderName: Authorization } }
    # 30 requests in progress per address (a WebSocket holds one while open).
    pryv-conn:
      inFlightReq: { amount: 30, sourceCriterion: { ipStrategy: { depth: 0 } } }
    # Request body cap: Pryv's uploads.maxSizeMb (50) plus 1 MiB (413 above).
    pryv-body:
      buffering: { maxRequestBodyBytes: 53477376, memRequestBodyBytes: 2097152 }

  routers:
    # Pryv matches paths regardless of letter case and with or without a
    # trailing slash: every pattern is case-insensitive ((?i)) and ends in
    # "/?$". Higher priority is tried first.
    pryv-login:
      rule: 'PathRegexp(`(?i)^(/[^/]+)?/(auth/login|mfa/(challenge|verify|confirm|recover|activate|deactivate))/?$`)'
      priority: 100
      middlewares: [pryv-conn, pryv-login, pryv-body]
      service: pryv-api
      tls: {}
    pryv-signup:
      rule: 'PathRegexp(`(?i)^(/[^/]+)?/account/(request-password-reset|reset-password|verify-email)/?$`) || PathRegexp(`(?i)^(/reg)?/(users?|email-challenge(/verify)?|access/invitationtoken/check)/?$`)'
      priority: 99
      middlewares: [pryv-conn, pryv-signup, pryv-body]
      service: pryv-api
      tls: {}
    pryv-access-create:
      rule: 'PathRegexp(`(?i)^/reg/access/?$`) && Method(`POST`)'
      priority: 98
      middlewares: [pryv-conn, pryv-access-create, pryv-body]
      service: pryv-api
      tls: {}
    pryv-access:
      rule: 'PathRegexp(`(?i)^/reg/access(/|$)`)'
      priority: 97
      middlewares: [pryv-conn, pryv-poll, pryv-body]
      service: pryv-api
      tls: {}
    pryv-admin-exempt:
      rule: 'PathRegexp(`(?i)^/(system|reg/admin)(/|$)`) && (ClientIP(`127.0.0.1`) || ClientIP(`::1`) || ClientIP(`10.0.0.0/8`))'
      priority: 96
      middlewares: [pryv-body]
      service: pryv-api
      tls: {}
    pryv-admin:
      rule: 'PathRegexp(`(?i)^/(system|reg/admin)(/|$)`)'
      priority: 95
      middlewares: [pryv-conn, pryv-admin, pryv-body]
      service: pryv-api
      tls: {}
    pryv-lookup:
      rule: 'PathRegexp(`(?i)^(/[^/]+)?/shared-secrets/retrieve/?$`) || PathRegexp(`(?i)^/reg(/|$)`) || PathRegexp(`(?i)^/auth/sso(/|$)`)'
      priority: 94
      middlewares: [pryv-conn, pryv-lookup, pryv-body]
      service: pryv-api
      tls: {}
    pryv-oauth-token:
      rule: 'PathRegexp(`(?i)^/oauth2/(token|introspect|revoke)/?$`)'
      priority: 93
      middlewares: [pryv-conn, pryv-oauth-token, pryv-body]
      service: pryv-api
      tls: {}
    pryv-oauth-auth:
      rule: 'PathRegexp(`(?i)^/oauth2/authorize(/|$)`)'
      priority: 92
      middlewares: [pryv-conn, pryv-oauth-auth, pryv-body]
      service: pryv-api
      tls: {}
    pryv-hfs-token:
      rule: 'PathRegexp(`(?i)^/[^/]+/(events/[^/]+/series|series/batch)(/|$)`) && HeaderRegexp(`Authorization`, `^(?:(?i:bearer|basic) +)?[^ ]+$`)'
      priority: 91
      middlewares: [pryv-conn, pryv-ip, pryv-hfs, pryv-body]
      service: pryv-hfs
      tls: {}
    pryv-hfs:
      rule: 'PathRegexp(`(?i)^/[^/]+/(events/[^/]+/series|series/batch)(/|$)`)'
      priority: 90
      middlewares: [pryv-conn, pryv-ip, pryv-body]
      service: pryv-hfs
      tls: {}
    pryv-socket:
      rule: 'PathPrefix(`/socket.io/`)'
      priority: 89
      middlewares: [pryv-conn, pryv-ip]
      service: pryv-api
      tls: {}
    pryv-read-token:
      rule: 'HeaderRegexp(`Authorization`, `^(?:(?i:bearer|basic) +)?[^ ]+$`) && (Method(`GET`) || Method(`HEAD`) || Method(`OPTIONS`))'
      priority: 20
      middlewares: [pryv-conn, pryv-ip, pryv-tok-read]
      service: pryv-api
      tls: {}
    pryv-write-token:
      rule: 'HeaderRegexp(`Authorization`, `^(?:(?i:bearer|basic) +)?[^ ]+$`)'
      priority: 19
      middlewares: [pryv-conn, pryv-ip, pryv-tok-write, pryv-body]
      service: pryv-api
      tls: {}
    pryv-read:
      rule: 'PathPrefix(`/`) && (Method(`GET`) || Method(`HEAD`) || Method(`OPTIONS`))'
      priority: 2
      middlewares: [pryv-conn, pryv-ip]
      service: pryv-api
      tls: {}
    pryv-write:
      rule: 'PathPrefix(`/`)'
      priority: 1
      middlewares: [pryv-conn, pryv-ip, pryv-body]
      service: pryv-api
      tls: {}

tls:
  certificates:
    - certFile: /etc/traefik/certs/fullchain.pem
      keyFile: /etc/traefik/certs/privkey.pem
```

Traefik reports configuration errors in its own log, at start and whenever the dynamic file changes (it is watched, so editing it applies it). Traefik 3.8 also logs that it may reject some encoded characters in request paths; keep that default, Pryv's routes need none of them.

**Username-in-host deployments.** The three changes listed for nginx apply: a wildcard certificate, the shorter paths on the reserved hosts `reg.`, `access.` and `mfa.` (add `Host(...)` to the routers that match `/reg/...` and give them the shorter paths), and the HFS paths of a user host sent to `pryv-api` (the core forwards them to the HFS worker). This shape was not part of the verified setup.

**Multi-core deployments.** The notes for nginx hold: one Traefik per core keeps the per-token limits exact. The `redis` option above also lets several Traefik instances share their counters.


## Caddy configuration

The same routes, keys and limits as the nginx configuration above (consumer health app profile), in one `Caddyfile`. Caddy has no rate limiting in its standard build: it needs the [caddy-ratelimit](https://github.com/mholt/caddy-ratelimit) module, a third-party module by Caddy's author, built in with `xcaddy build --with github.com/mholt/caddy-ratelimit` or with Caddy's builder image:

```dockerfile
FROM caddy:2.11-builder AS builder
RUN xcaddy build --with github.com/mholt/caddy-ratelimit
FROM caddy:2.11
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
```

It was verified with Caddy 2.11.9 in front of an open-pryv.io 2.0.0-rc.87 core in DNSless mode, with the same assumptions as for nginx: Caddy terminates TLS, and Pryv listens on plain HTTP on `127.0.0.1:3000` (API) and `127.0.0.1:4000` (HFS).

What differs from nginx:

- **Windows instead of buckets.** A zone allows at most `events` requests in any `window`. Each limit below is the nginx burst over the time the nginx rate takes to refill it: `10r/m, burst 5` becomes "5 in 30 seconds". Refused requests are not counted, so a client that keeps sending gets through again as soon as its oldest request leaves the window.
- **One class per request.** Caddy gives each request a route class once (the second `map`), and every zone matches on that class. Zones are shared by name, so the per-IP backstop is one counter for data, HFS and socket.io traffic.
- **The token read the way Pryv reads it**, header first then `?auth=`, as with nginx: a token sent bare, as `Bearer`, with a trailing caller id, or as `?auth=` counts against one bucket (Basic, keyed on the encoded credentials, gets its own). A request without a token only meets the per-IP backstop.
- **No connection cap.** Caddy has no per-address limit on concurrent connections or requests. Pryv's own ceilings apply (calls in progress per account and per access, socket.io connections per access); a host firewall can cap connections per address (for example an nftables rule with `ct count`).
- **Body size.** `request_body` refuses a request body over 51 MiB with `413`, chunked bodies included.
- **Logs.** The access log is JSON, the URI is logged without its query string, and Caddy writes the `Authorization` header as `REDACTED`. A request refused by a limit carries `"lr":"REJECTED"` and the zone's name; the [fail2ban filters for Caddy](#caddy-filters) read it.

```text
# /etc/caddy/Caddyfile  (Caddy 2.10 or later, built with caddy-ratelimit)
{
	servers {
		timeouts {
			# A client must send its whole request head within 15 s (slow-loris).
			read_header 15s
			idle 65s
		}
	}
}

core.example.com {
	tls /etc/caddy/certs/fullchain.pem /etc/caddy/certs/privkey.pem

	# ---------- Access log without query strings ----------
	# The query string can carry `auth=<token>`, which must not land in a log
	# file: it is cut from the logged URI. Caddy already writes the
	# Authorization header as REDACTED. A request refused by a limit below
	# carries `"lr":"REJECTED"` and the name of the limit in `zone`; the
	# fail2ban filters read this file.
	log {
		output file /var/log/caddy/pryv-access.log
		format filter {
			wrap json
			fields {
				request>uri regexp \?.*$ ""
			}
		}
	}

	# ---------- Bodies ----------
	# Pryv's uploads.maxSizeMb (default 50) caps each uploaded file and the
	# JSON body; Caddy caps the whole request at the Pryv limit plus 1 MiB of
	# multipart overhead (413 above it).
	request_body {
		max_size 51MiB
	}

	# ---------- The access token, read the way Pryv reads it ----------
	# Header first: "Bearer <t>", "Basic <b64>", or the bare token (a trailing
	# " <callerId>" is ignored). Otherwise the `auth` query parameter. Basic is
	# keyed on the encoded credentials: still one bucket per token, but not
	# the same bucket as the bare token.
	map {header.Authorization} {pryv_tok} {
		~(?i)^(?:bearer|basic)\s+(\S+) "${1}"
		~^(\S+) "${1}"
		default {query.auth}
	}

	# ---------- Route classes ----------
	# Pryv matches paths regardless of letter case and with or without a
	# trailing slash, so every pattern is case-insensitive ((?i)) and ends in
	# "/?$": /alice/Auth/Login/ must not escape the login limit. The first
	# line that matches gives the class.
	map {method}{path} {pryv_class} {
		~(?i)^[A-Z]+(/[^/]+)?/(auth/login|mfa/(challenge|verify|confirm|recover|activate|deactivate))/?$ login
		~(?i)^[A-Z]+(/[^/]+)?/account/(request-password-reset|reset-password|verify-email)/?$ signup
		~(?i)^[A-Z]+(/reg)?/(users?|email-challenge(/verify)?|access/invitationtoken/check)/?$ signup
		~(?i)^[A-Z]+(/[^/]+)?/shared-secrets/retrieve/?$ lookup
		~(?i)^POST/reg/access/?$ access_create
		~(?i)^[A-Z]+/reg/access(/|$) access
		~(?i)^[A-Z]+/(system|reg/admin)(/|$) admin
		~(?i)^[A-Z]+/reg(/|$) lookup
		~(?i)^[A-Z]+/oauth2/(token|introspect|revoke)/?$ oauth_token
		~(?i)^[A-Z]+/oauth2/authorize(/|$) oauth_auth
		~(?i)^[A-Z]+/auth/sso(/|$) lookup
		~(?i)^[A-Z]+/[^/]+/(events/[^/]+/series|series/batch)(/|$) hfs
		~(?i)^[A-Z]+/socket\.io/ socket
		~^(GET|HEAD|OPTIONS)/ data_read
		default data_write
	}

	# ---------- Limits (consumer health app profile) ----------
	# A sliding window: at most `events` requests in any `window`. Each limit
	# is the nginx burst over the time the nginx rate takes to refill it, so
	# "10r/m, burst 5" is 5 in 30 s. Refused requests are not counted.
	# Zones are keyed on the client address unless `key` names the token.
	rate_limit {
		zone pryv_login {
			match {
				vars {pryv_class} login
			}
			key {client_ip}
			events 5
			window 30s
		}
		zone pryv_signup {
			match {
				vars {pryv_class} signup
			}
			key {client_ip}
			events 3
			window 1m
		}
		zone pryv_lookup {
			match {
				vars {pryv_class} lookup
			}
			key {client_ip}
			events 20
			window 20s
		}
		zone pryv_access_create {
			match {
				vars {pryv_class} access_create
			}
			key {client_ip}
			events 5
			window 50s
		}
		zone pryv_poll {
			match {
				vars {pryv_class} access access_create
			}
			key {client_ip}
			events 10
			window 3s
		}
		# Hosts exempt from the admin limit: your cores (they call each other's
		# /system routes) and your administration hosts. Replace the example range.
		zone pryv_admin {
			match {
				vars {pryv_class} admin
				not client_ip 127.0.0.1 ::1 10.0.0.0/8
			}
			key {client_ip}
			events 20
			window 40s
		}
		zone pryv_oauth_token {
			match {
				vars {pryv_class} oauth_token
			}
			key {client_ip}
			events 10
			window 10s
		}
		zone pryv_oauth_auth {
			match {
				vars {pryv_class} oauth_auth
			}
			key {client_ip}
			events 30
			window 6s
		}
		# Per IP (backstop, also covers requests without a token), and per
		# token with separate read and write budgets. A batch call
		# (POST /{username}/) counts as one write however many methods it carries.
		zone pryv_ip {
			match {
				vars {pryv_class} data_read data_write hfs socket
			}
			key {client_ip}
			events 100
			window 5s
		}
		zone pryv_tok_read {
			match {
				vars {pryv_class} data_read
				not vars {pryv_tok} ""
			}
			key {pryv_tok}
			events 40
			window 4s
		}
		zone pryv_tok_write {
			match {
				vars {pryv_class} data_write
				not vars {pryv_tok} ""
			}
			key {pryv_tok}
			events 20
			window 4s
		}
		zone pryv_hfs {
			match {
				vars {pryv_class} hfs
				not vars {pryv_tok} ""
			}
			key {pryv_tok}
			events 20
			window 4s
		}
	}

	# ---------- Refusal ----------
	# A JSON 429 shaped like Pryv's own errors, readable by browser apps.
	# Pryv's own 429s (MFA backoff, access-request ceiling, calls in progress
	# per account or access) pass through untouched: they are responses, not
	# Caddy errors.
	handle_errors 429 {
		log_append lr REJECTED
		log_append zone {http.rate_limit.exceeded.name}
		header Access-Control-Allow-Origin "*"
		header Access-Control-Expose-Headers "Retry-After"
		header Content-Type application/json
		respond `{"error":{"id":"too-many-requests","message":"Rate limit reached, retry later."}}` 429
	}

	# ---------- Headers and upstreams ----------
	# Caddy sets X-Forwarded-For to the client address (a client's own value
	# is dropped, as no proxy in front is trusted), X-Forwarded-Host to the
	# Host received and X-Forwarded-Proto: what Pryv expects. Host is passed
	# as received (hosted sites and user subdomains are recognised by it).
	@hfs vars {pryv_class} hfs
	handle @hfs {
		# High-frequency series (HFS worker). Host is the worker's own address
		# (see the HFS note for nginx).
		reverse_proxy 127.0.0.1:4000 {
			header_up Host 127.0.0.1:4000
		}
	}
	handle {
		reverse_proxy 127.0.0.1:3000 {
			# Idle time between two reads from Pryv; large event queries
			# stream, which keeps the timer fed. From the release after
			# 2.0.0-rc.89 the core itself also closes a connection idle either
			# way for http.responseIdleTimeoutMs (120 s): keep both above
			# your slowest call.
			transport http {
				read_timeout 120s
			}
		}
	}
}
```

Check the file with `caddy validate --config /etc/caddy/Caddyfile` and apply it with `systemctl reload caddy` (or `caddy reload --config /etc/caddy/Caddyfile`). Caddy obtains and renews certificates itself when the `tls` line is left out, see [composing with TLS](#composing-with-tls).

**Username-in-host deployments.** The three changes listed for nginx apply: a wildcard certificate, the shorter paths on the reserved hosts `reg.`, `access.` and `mfa.` (a second site block for those names, with the same zones and the shorter paths in its class map), and the HFS paths of a user host sent to `127.0.0.1:3000` (the core forwards them to the HFS worker). This shape was not part of the verified setup.

**Multi-core deployments.** The notes for nginx hold: one Caddy per core keeps the per-token limits exact. The module's `distributed` option shares its counters between Caddy instances that use the same storage (not part of the verified setup).


## Cloudflare in front

Unlike the configurations above, this section was not tested in front of a core: it follows Cloudflare's documentation as of November 2026. Check it against your plan before relying on it.

**What a plan allows.** Cloudflare's [rate limiting rules](https://developers.cloudflare.com/waf/rate-limiting-rules/) count requests per client IP on every plan, with 1 rule and a 10-second period on Free, 2 rules on Pro and 5 on Business. Regular expressions (the `matches` operator) need Business or Enterprise. Counting per request header or query parameter, which is what per-token limits need (the `Authorization` header or the `auth` parameter), needs Enterprise with Advanced Rate Limiting. So on most plans Cloudflare carries the per-IP limits of the unauthenticated routes, and the per-token limits stay on a proxy behind it (any of the configurations above) or with Pryv's in-process limits only.

**The client address.** Cloudflare reaches your origin from [its published ranges](https://www.cloudflare.com/ips/), sends the client's address in `CF-Connecting-IP`, and appends the address it saw to `X-Forwarded-For`.

- With a proxy behind Cloudflare, have it restore the client address from Cloudflare's ranges only: for nginx, one `set_real_ip_from` line per range and `real_ip_header CF-Connecting-IP;`, then overwrite `X-Forwarded-For` toward the core as shown above.
- With Cloudflare straight to the core, list Cloudflare's ranges in `http.trustedProxies`. Pryv reads `X-Forwarded-For` from the right, so the last address, appended by Cloudflare, is the client even when the client sent a header of its own.
- Either way, firewall the origin so that it accepts connections from Cloudflare's ranges only, or clients bypass Cloudflare and its limits. Keep the list current: Cloudflare changes its ranges from time to time.

**Example rules** (Business plan, consumer profile, characteristic *IP*, period 60 seconds, action *Block*). Paths are lowered first, because Pryv matches them regardless of case and with or without a trailing slash. The optional first segment covers both URL shapes (username in the path or in the host).

Login and MFA, 15 requests per period (nginx `10r/m, burst 5`):

```txt
http.request.method eq "POST" and lower(http.request.uri.path) matches "^/([^/]+/)?(auth/login|mfa/(challenge|verify|confirm|recover|activate|deactivate))/?$"
```

Registration and password reset, 6 requests per period (nginx `3r/m, burst 3`):

```txt
http.request.method eq "POST" and (
  lower(http.request.uri.path) matches "^/(reg/)?(users|user|email-challenge(/verify)?)/?$"
  or lower(http.request.uri.path) matches "^/([^/]+/)?account/(request-password-reset|reset-password|verify-email)/?$"
  or lower(http.request.uri.path) matches "^/access/invitationtoken/check/?$"
)
```

Access-request creation, 11 requests per period (nginx `6r/m, burst 5`):

```txt
http.request.method eq "POST" and lower(http.request.uri.path) matches "^/reg/access/?$"
```

On the reserved hosts of a username-in-host deployment (`reg.`, `access.`, `mfa.`), the `/reg` prefix is implied: add `http.host` conditions with the shorter paths. Requests Cloudflare refuses never reach the core, so they appear in Cloudflare's logs, not in Pryv's audit log.


## Composing with TLS

**nginx terminates TLS (the configuration above).** Pryv runs on plain HTTP (`http.port: 3000`, no `http.ssl` block). You can still let Pryv manage the certificate:

- Keep `letsEncrypt.enabled: true`. The renewer writes the certificate to `var-pryv/tls/<hostname>/fullchain.pem` and `privkey.pem` (under `letsEncrypt.tlsDir`); point `ssl_certificate` and `ssl_certificate_key` there, and set `letsEncrypt.onRotateScript` to a script running `nginx -t && nginx -s reload` (see [SSL certificate](/customer-resources/ssl-certificate/#strategy-a--built-in-auto-renewal-recommended)).
- With HAProxy, `crt` names one file holding the chain followed by the key: have the `onRotateScript` write it (`cat fullchain.pem privkey.pem > /etc/haproxy/certs/core.example.com.pem`), then run `haproxy -c -f /etc/haproxy/haproxy.cfg && systemctl reload haproxy`.
- Traefik and Caddy can obtain and renew certificates themselves instead (Traefik's ACME certificate resolvers; Caddy's automatic HTTPS, when the site block has no `tls` line), which needs ports 80 and 443 to reach the proxy for HTTP-01: then leave `letsEncrypt.enabled: false` in Pryv. Pointing them at the files of Pryv's renewer works as for nginx (Traefik's `tls.certificates`, Caddy's `tls` line, an `onRotateScript` that reloads the proxy), but was not part of the verified setup.
- With **DNS-01** (wildcard, username-in-host deployments) nothing else changes.
- With **HTTP-01** (single host name), Pryv answers the challenge on its own listener bound to port 80. nginx must then not listen on port 80: drop the redirect server block (with HAProxy, the `bind :80` line). Pryv's port-80 listener answers 404 to everything but the challenge, so plain-HTTP clients get no redirect to HTTPS. If you need that redirect, issue the certificate outside Pryv instead (certbot, or an ACME-capable proxy) and leave `letsEncrypt.enabled: false`.

**Pryv terminates TLS itself** (`http.port: 443` with `http.ssl`, often with the built-in renewer). An HTTP-aware proxy cannot sit in front without taking over TLS, because it cannot read paths or headers inside a connection it does not decrypt. Your options:

1. **Move TLS to nginx** (recommended). Switch Pryv to `http.ip: 127.0.0.1`, `http.port: 3000`, remove the `http.ssl` block, and follow the bullet points above to keep the built-in renewer. This is the only option that gives per-route and per-token limits.
2. **TCP passthrough** with nginx's `stream` module in front of port 443. nginx can then cap concurrent connections per IP (`limit_conn` in the `stream` context) and nothing else: no routes, no tokens, no 429. Worse, Pryv then sees nginx's address as the client of every request, in its audit log too; Pryv does not read the PROXY protocol. Use this only as a stopgap.
3. **No proxy.** You keep Pryv's in-process limits listed at the top, plus whatever the host firewall can do per IP at the connection level. Keep `http.trustedProxies` at its default: the core then ignores a client's own `X-Forwarded-For` and records the TCP peer. On cores before open-pryv.io 2.0.0-rc.36, any client could choose the IP recorded for its requests; there, treat the audit log's source IP as unverified.


## fail2ban

Three jails, all reading the proxy's logs (Pryv's own logs are not involved). Install the filters, then the jail file, then `fail2ban-client reload`. The filters and jails below read nginx's logs; with HAProxy, Traefik or Caddy, use the [HAProxy filters](#haproxy-filters), [Traefik filters](#traefik-filters) or [Caddy filters](#caddy-filters) instead.

### Filters

```ini
# /etc/fail2ban/filter.d/pryv-auth-login-fail.conf
# Reads the nginx access log (log_format pryv).
# Paths are matched case-insensitively and with an optional trailing slash,
# as Pryv routes them.
# auth/login: 401 = wrong password; 404 = unknown username (enumeration).
# mfa/verify, confirm, recover: 400 = wrong MFA code or wrong recovery code
# (also a malformed request); 401 = wrong password (recover), or an MFA
# session ended by too many wrong codes; 404 = unknown username.
[Definition]
failregex = ^<HOST> - \[\] "POST (?i:(?:/[^/" ]+)?/auth/login/?) HTTP/[\d.]+" (?:401|404) 
            ^<HOST> - \[\] "POST (?i:(?:/[^/" ]+)?/mfa/(?:verify|confirm|recover)/?) HTTP/[\d.]+" (?:400|401|404) 
ignoreregex =
datepattern = ^[^\[]*\[({DATE})
              {^LN-BEG}
```

```ini
# /etc/fail2ban/filter.d/pryv-excess-rate.conf
# Reads the nginx error log, where limit_req and limit_conn log rejections.
# Only the per-IP zones of unauthenticated surfaces: an app exceeding its
# per-token budget gets 429s, not an IP ban.
[Definition]
failregex = ^\s*\[[a-z]+\] \d+#\d+: \*\d+ limiting requests, excess: [\d.]+ by zone "pryv_(?:login|signup|lookup|access_create|oauth_token|oauth_auth|admin)", client: <HOST>,
            ^\s*\[[a-z]+\] \d+#\d+: \*\d+ limiting connections by zone "pryv_conn", client: <HOST>,
ignoreregex =
```

```ini
# /etc/fail2ban/filter.d/pryv-access-create-abuse.conf
# Reads the nginx access log. Counts access-request CREATIONS (201) and
# refused creations (429, either Pryv's full queue or nginx's own
# pryv_access_create limit), per source address. Polling (GET) and
# accept/refuse (POST /reg/access/{key}) are not counted.
[Definition]
failregex = ^<HOST> - \[\] "POST (?i:(?:/reg)?/access/?) HTTP/[\d.]+" (?:201|429) 
ignoreregex =
datepattern = ^[^\[]*\[({DATE})
              {^LN-BEG}
```

### Jails

```ini
# /etc/fail2ban/jail.d/pryv.local
[DEFAULT]
# Never ban yourself, your cores, your monitoring, or a customer's
# known egress address (a hospital NAT, for instance).
ignoreip = 127.0.0.1/8 ::1 10.0.0.0/8
banaction = nftables-multiport
port = http,https

# 5 failed logins within 10 minutes from one address: banned for 1 hour.
[pryv-auth-login-fail]
enabled  = true
filter   = pryv-auth-login-fail
logpath  = /var/log/nginx/pryv-access.log
maxretry = 5
findtime = 10m
bantime  = 1h

# Repeatedly hitting the per-IP limits on unauthenticated routes: the
# limiter already refuses each request, the ban stops the traffic early.
[pryv-excess-rate]
enabled  = true
filter   = pryv-excess-rate
logpath  = /var/log/nginx/pryv-error.log
maxretry = 10
findtime = 10m
bantime  = 1h

# 30 access-request creations in 10 minutes from one address.
[pryv-access-create-abuse]
enabled  = true
filter   = pryv-access-create-abuse
logpath  = /var/log/nginx/pryv-access.log
maxretry = 30
findtime = 10m
bantime  = 1h
```

### HAProxy filters

The same three jails, reading the HAProxy log line of the [HAProxy configuration](#haproxy-configuration) through syslog (`common.conf` strips the syslog prefix). There is no error log to read: the excess-rate filter counts the refusals HAProxy logs with `lr=REJECTED` and the name of a per-IP limit.

```ini
# /etc/fail2ban/filter.d/pryv-haproxy-auth-login-fail.conf
# Same statuses as pryv-auth-login-fail above.
[INCLUDES]
before = common.conf
[Definition]
_daemon = haproxy
failregex = ^%(__prefix_line)s<HOST> - \[[^\]]*\] "POST (?i:(?:/[^/" ]+)?/auth/login/?) HTTP/[\d.]+" (?:401|404) 
            ^%(__prefix_line)s<HOST> - \[[^\]]*\] "POST (?i:(?:/[^/" ]+)?/mfa/(?:verify|confirm|recover)/?) HTTP/[\d.]+" (?:400|401|404) 
ignoreregex =
```

```ini
# /etc/fail2ban/filter.d/pryv-haproxy-excess-rate.conf
# Only the per-IP limits of unauthenticated surfaces and the connection cap:
# an app exceeding its per-token budget gets 429s, not an IP ban.
[INCLUDES]
before = common.conf
[Definition]
_daemon = haproxy
failregex = ^%(__prefix_line)s<HOST> - \[[^\]]*\] "[A-Z]+ [^"]*" 429 \d+ lr=REJECTED zone=pryv_(?:login|signup|lookup|access_create|oauth_token|oauth_auth|admin|conn) 
ignoreregex =
```

```ini
# /etc/fail2ban/filter.d/pryv-haproxy-access-create-abuse.conf
# Access-request creations (201) and refused creations (429, Pryv's or HAProxy's).
[INCLUDES]
before = common.conf
[Definition]
_daemon = haproxy
failregex = ^%(__prefix_line)s<HOST> - \[[^\]]*\] "POST (?i:(?:/reg)?/access/?) HTTP/[\d.]+" (?:201|429) 
ignoreregex =
```

In the jail file above, name these filters (`filter = pryv-haproxy-auth-login-fail`, ...) and read `/var/log/haproxy.log` for all three (`logpath`).

### Traefik filters

The same three jails, reading the JSON access log of the [Traefik configuration](#traefik-configuration). There is no error log to read: the excess-rate filter counts the refusals Traefik answered itself (`OriginStatus` 0) on the routers of unauthenticated surfaces.

```ini
# /etc/fail2ban/filter.d/pryv-traefik-auth-login-fail.conf
# Same statuses as pryv-auth-login-fail above.
[Definition]
failregex = ^\{"ClientHost":"<HOST>","DownstreamStatus":(?:401|404),[^}]*"RequestMethod":"POST","RequestPath":"(?i:(?:/[^/"]+)?/auth/login/?)",
            ^\{"ClientHost":"<HOST>","DownstreamStatus":(?:400|401|404),[^}]*"RequestMethod":"POST","RequestPath":"(?i:(?:/[^/"]+)?/mfa/(?:verify|confirm|recover)/?)",
ignoreregex =
datepattern = "time":"%%Y-%%m-%%dT%%H:%%M:%%S%%z"
```

```ini
# /etc/fail2ban/filter.d/pryv-traefik-excess-rate.conf
# Refusals by Traefik itself (OriginStatus 0) on the routers of
# unauthenticated surfaces: an app exceeding its per-token budget gets 429s,
# not an IP ban.
[Definition]
failregex = ^\{"ClientHost":"<HOST>","DownstreamStatus":429,[^}]*"OriginStatus":0,[^}]*"RouterName":"pryv-(?:login|signup|lookup|access-create|oauth-token|oauth-auth|admin)@file"
ignoreregex =
datepattern = "time":"%%Y-%%m-%%dT%%H:%%M:%%S%%z"
```

```ini
# /etc/fail2ban/filter.d/pryv-traefik-access-create-abuse.conf
# Access-request creations (201) and refused creations (429, Pryv's or Traefik's).
[Definition]
failregex = ^\{"ClientHost":"<HOST>","DownstreamStatus":(?:201|429),[^}]*"RequestMethod":"POST","RequestPath":"(?i:(?:/reg)?/access/?)",
ignoreregex =
datepattern = "time":"%%Y-%%m-%%dT%%H:%%M:%%S%%z"
```

In the jail file above, name these filters (`filter = pryv-traefik-auth-login-fail`, ...) and read `/var/log/traefik/pryv-access.log` for all three (`logpath`).

### Caddy filters

The same three jails, reading the JSON access log of the [Caddy configuration](#caddy-configuration). The excess-rate filter counts the refusals Caddy logs with `"lr":"REJECTED"` and the name of a per-IP zone. Caddy writes its timestamps with more digits than fail2ban reads, which the filters allow for.

```ini
# /etc/fail2ban/filter.d/pryv-caddy-auth-login-fail.conf
# Same statuses as pryv-auth-login-fail above.
[Definition]
_req = ^\{"level":"\w+",(?:"ts":)?[\d.]*,"logger":"[^"]*","msg":"handled request","request":\{"remote_ip":"[^"]*","remote_port":"[^"]*","client_ip":"<HOST>","proto":"[^"]*",
failregex = %(_req)s"method":"POST","host":"[^"]*","uri":"(?i:(?:/[^/"]+)?/auth/login/?)",.*"status":(?:401|404),
            %(_req)s"method":"POST","host":"[^"]*","uri":"(?i:(?:/[^/"]+)?/mfa/(?:verify|confirm|recover)/?)",.*"status":(?:400|401|404),
ignoreregex =
datepattern = "ts":{EPOCH}
```

```ini
# /etc/fail2ban/filter.d/pryv-caddy-excess-rate.conf
# Refusals by Caddy's per-IP limits on unauthenticated surfaces: an app
# exceeding its per-token budget gets 429s, not an IP ban.
[Definition]
_req = ^\{"level":"\w+",(?:"ts":)?[\d.]*,"logger":"[^"]*","msg":"handled request","request":\{"remote_ip":"[^"]*","remote_port":"[^"]*","client_ip":"<HOST>","proto":"[^"]*",
failregex = %(_req)s.*"status":429,.*"zone":"pryv_(?:login|signup|lookup|access_create|oauth_token|oauth_auth|admin)","lr":"REJECTED"\}$
ignoreregex =
datepattern = "ts":{EPOCH}
```

```ini
# /etc/fail2ban/filter.d/pryv-caddy-access-create-abuse.conf
# Access-request creations (201) and refused creations (429, Pryv's or Caddy's).
[Definition]
_req = ^\{"level":"\w+",(?:"ts":)?[\d.]*,"logger":"[^"]*","msg":"handled request","request":\{"remote_ip":"[^"]*","remote_port":"[^"]*","client_ip":"<HOST>","proto":"[^"]*",
failregex = %(_req)s"method":"POST","host":"[^"]*","uri":"(?i:(?:/reg)?/access/?)",.*"status":(?:201|429),
ignoreregex =
datepattern = "ts":{EPOCH}
```

In the jail file above, name these filters (`filter = pryv-caddy-auth-login-fail`, ...) and read `/var/log/caddy/pryv-access.log` for all three (`logpath`).

If the proxy runs in Docker with published ports, bans must go to the `DOCKER-USER` chain (for example `banaction = iptables-multiport` with `chain = DOCKER-USER`), or they never see the traffic.

Pryv's audit log also records the source IP of every audited API call, for your SIEM. fail2ban reads the nginx logs here because they cover requests that never reach Pryv, and failed logins for usernames that do not exist (which have no per-user audit log to write to).


## Logs are personal data

IP addresses in the nginx logs and the fail2ban database are personal data in most regimes. Rotate them on a schedule you have documented (`logrotate`, `dbpurgeage` in `fail2ban.conf`), and keep them in the same region as the core they protect when you operate cores under different data-residency rules. The log format above leaves query strings out so that tokens passed as `?auth=` never reach the access log; the error log still records the full request line of a refused request, so prefer the `Authorization` header in your apps. The HAProxy log line, and the Traefik and Caddy access logs, leave query strings out of every line, refusals included; Traefik writes no request header, Caddy writes the `Authorization` header as `REDACTED`. Caddy rolls its log files itself (`roll_size`, `roll_keep` in the `output file` block); Traefik reopens its access log on `USR1`, which is what a `logrotate` postrotate step sends.


## Limits at a glance

The configuration above is the consumer profile. Edit the `rate=` values in the zones and the `burst=` values in the locations for the others. With HAProxy, each limit is the rate over its table's window plus the burst (`10r/m, burst 10` is "more than 20 in one minute"; `50r/s, burst 500` on a 10-second window is "more than 1000"); the connection cap is the same number. With Traefik, `average` and `burst` are the nginx rate and burst as they are, and `period` the unit of the rate. With Caddy, each limit is the burst over the time the rate takes to refill it (`10r/m, burst 10` is 10 in one minute; `50r/s, burst 500` is 500 in 10 seconds); Caddy has no connection cap.

| Setting | Consumer health app | B2B research consortium | Hospital deployment |
|---|---|---|---|
| Who calls | many individuals, mostly mobile | few organisations, scripted imports from a handful of addresses | staff behind a few hospital egress addresses, bedside devices |
| `pryv_login` (login, MFA), per IP | 10r/m, burst 5 | 10r/m, burst 10 | 60r/m, burst 30 |
| `pryv_signup` (registration, reset), per IP | 3r/m, burst 3 | 1r/m, burst 2 (accounts provisioned by admins) | 5r/m, burst 5 |
| `pryv_lookup`, per IP | 1r/s, burst 20 | 1r/s, burst 10 | 5r/s, burst 50 |
| `pryv_access_create` (POST), per IP | 6r/m, burst 5 | 6r/m, burst 10 | 30r/m, burst 30 |
| `pryv_poll`, per IP | 3r/s, burst 10 | 3r/s, burst 10 | 20r/s, burst 50 |
| `pryv_tok_write`, per token | 5r/s, burst 20 | 50r/s, burst 500 | 10r/s, burst 50 |
| `pryv_tok_read`, per token | 10r/s, burst 40 | 50r/s, burst 200 | 30r/s, burst 100 |
| `pryv_hfs`, per token | 5r/s, burst 20 | 100r/s, burst 1000 | 20r/s, burst 200 |
| `pryv_ip` backstop, per IP | 20r/s, burst 100 | 200r/s, burst 1000 | 200r/s, burst 1000 |
| `limit_conn pryv_conn`, per IP | 30 | 100 | 1000, or hospital ranges exempt |
| `client_max_body_size` / `uploads.maxSizeMb` | 11m / 10 if apps upload only photos, else 51m / 50 | 51m / 50 | 51m / 50 |
| `pryv-auth-login-fail` | 5 in 10 min, ban 1 h | 5 in 10 min, ban 1 h | 20 in 10 min, ban 15 min, hospital egress in `ignoreip` |
| `pryv-excess-rate` | 10 in 10 min, ban 1 h | 10 in 10 min, ban 1 h | 30 in 10 min, ban 15 min |
| `pryv-access-create-abuse` | 30 in 10 min, ban 1 h | 30 in 10 min, ban 1 h | 200 in 10 min, ban 15 min |
| `services.mfa.attempts.backoff` | default | default | default (it is per account, so a shared address does not trip it) |
| `auth.passwordAttempts` (per account) | default | default | default (per account, as above) |
| `auth.passwordAttempts.perIp.maxFailures` | default (30 in 15 min) | default | raise it (or `0`) for the hospital egress addresses, see below |

Trade-offs to keep in mind:

- **Shared addresses.** Mobile carriers put many subscribers behind one address (carrier-grade NAT), and hospitals put all staff behind a few. Per-IP limits and IP bans then hit everyone behind it. Keep per-IP limits for the unauthenticated surfaces, where there is nothing better to key on, and rely on per-token limits for data traffic. For known shared addresses, raise the limits through a `geo` map (as done for the admin zone) and list them in `ignoreip`. Pryv's own per-address password budget (`auth.passwordAttempts.perIp`) counts every failed password from such an address together: 30 typos across a hospital in 15 minutes refuse every password check from it until the window ends. It is one setting for all addresses, so where staff share a few egress addresses, raise `maxFailures` or set it to `0` and rely on the per-account delays and on your proxy limits. The same holds for the registration codes per address (`account.emailVerification.registrationCodesPerIpPerHour`, 10 an hour) and the unknown account names per address (`limits.routing.unknownNamesPerClientPerMinute`, 60 a minute): raise them for a clinic or campus that registers or mistypes many accounts from one address.
- **IPv6.** `$binary_remote_addr` is a full /128 address and a single host usually controls a whole /64. If you see abuse rotating through one prefix, key the per-IP zones on the /64 instead (a `map` on `$remote_addr` keeping the first four groups).
- **Bursts versus rates.** The rate is what a client can sustain; the burst is how far ahead of it a client may go before refusals start. Batch importers need large bursts; login needs a small one. Too small a burst on read zones breaks apps that load a dashboard with a dozen parallel calls.


## Verify the limits fire

Test against a staging core, from an address you can afford to have banned (or add it to `ignoreip` while testing the limits, and remove it again to test the bans). The commands use [vegeta](https://github.com/tsenart/vegeta), a single binary with no account (`brew install vegeta`, or a release binary from GitHub), and `jq`.

**1. Login limit, per IP.** 5 attempts per second for 30 seconds against the `10r/m, burst 5` zone: about 10 requests are let through (the burst, plus 5 refills in 30 seconds) and reach Pryv, which answers them with `401`; the other 140 or so get `429` from nginx. On open-pryv.io 2.0.0-rc.47 or later, once the account's password delay has started (after 5 failures), Pryv answers one or two of the late ones with its own `429 too-many-attempts`: nginx's refusals are the ones with `too-many-requests` in the body and `lr=REJECTED` in the access log.

```bash
cat > login.json <<'EOF'
{"username":"ratetest","password":"wrong-password","appId":"rate-limit-test"}
EOF
echo 'POST https://core.example.com/ratetest/auth/login
Content-Type: application/json
Origin: https://core.example.com
@login.json' \
  | vegeta attack -rate=5/s -duration=30s \
  | vegeta report -type=json | jq '.status_codes'
# expect something like: { "401": 10, "429": 140 }  (404 instead of 401 if the user does not exist)
```

With HAProxy, the first 15 requests of the minute reach Pryv and every later one in the run is refused (refused requests count in the window): about 15 answered by Pryv (`401`, or Pryv's own `429` once the account's delay has started) and 135 `429` from HAProxy, whose log shows `lr=REJECTED zone=pryv_login` for its own.

Traefik gives nginx's counts (about 10 and 140), its refusals logged with `"OriginStatus":0`. With Caddy, 5 requests reach Pryv (5 in any 30 seconds) and about 145 are refused, logged with `"zone":"pryv_login"`.

**2. Write limit, per token.** The token does not have to be valid: nginx counts it before Pryv checks it, and an invalid token creates no data. 30 writes per second for 10 seconds against `5r/s, burst 20`: about 70 reach Pryv (and are refused by it with `403 invalid-access-token`), about 230 get `429`.

```bash
echo '{"streamIds":["diary"],"type":"note/txt","content":"x"}' > event.json
echo 'POST https://core.example.com/ratetest/events
Content-Type: application/json
Authorization: rate-limit-test-token
@event.json' \
  | vegeta attack -rate=30/s -duration=10s \
  | vegeta report -type=json | jq '.status_codes'
# expect something like: { "403": 70, "429": 230 }
```

Run it a second time with `?auth=rate-limit-test-token` in the URL and no `Authorization` header: the counts must be the same, which proves the query-string token is keyed too. HAProxy gives the same counts (70 is the limit of its 10-second window); for a second run wait 10 seconds, or the per-IP backstop (300 in 10 seconds) is already spent.

Traefik gives nginx's counts with the header. With `?auth=` it does not key the token (see [Traefik configuration](#traefik-configuration)): only the per-IP backstop applies, and nearly all 300 requests reach Pryv. With Caddy, about 40 reach Pryv and 260 are refused, the same with `?auth=`: the token zone allows 20 in 4 seconds, and the per-IP backstop (100 in 5 seconds) counts the requests the token zone then refuses. Wait 5 seconds between two runs.

With a **valid** token and slow calls, from 2.0.0-rc.90, Pryv may refuse some calls itself: past 32 calls in progress on one access (64 on one account) a worker answers `429 too-many-requests` without running the call. The body is the same as nginx's; tell them apart by the access log, where nginx's refusals show `lr=REJECTED` and Pryv's show `lr=PASSED`.

**3. The jails.** fail2ban never bans the addresses of the host it runs on (`ignoreself = true`, the default): run the test from another machine, or set `ignoreself = false` in the jail file while testing. Check each filter against the real logs (with HAProxy, the `pryv-haproxy-*` filters against `/var/log/haproxy.log`; with Traefik or Caddy, the `pryv-traefik-*` or `pryv-caddy-*` filters against their access log), then watch a ban happen:

```bash
fail2ban-regex /var/log/nginx/pryv-access.log /etc/fail2ban/filter.d/pryv-auth-login-fail.conf
fail2ban-regex /var/log/nginx/pryv-error.log  /etc/fail2ban/filter.d/pryv-excess-rate.conf
fail2ban-client status pryv-auth-login-fail
fail2ban-client set pryv-auth-login-fail unbanip 203.0.113.7   # undo a test ban
```

Run step 1 again with the jails enabled and your test address out of `ignoreip`: `pryv-auth-login-fail` bans it after the fifth failed login, a second or two into the run, and the rest of the run fails with connection errors (vegeta reports them as status `0`) instead of `401` and `429`. The ban then usually cuts the traffic before `pryv-excess-rate` has counted its 10 rejections; that jail is for clients that stay under the login-failure threshold, and shows in `fail2ban-regex` above. Each jail bans only ports 80 and 443 (`port = http,https`).

Without vegeta, a plain `curl` loop shows the same thing:

```bash
for i in $(seq 1 20); do
  curl -s -o /dev/null -w '%{http_code}\n' -X POST https://core.example.com/ratetest/auth/login \
    -H 'Content-Type: application/json' -d @login.json
done | sort | uniq -c
```
