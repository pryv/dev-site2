---
title: 'Rate limiting and DoS protection'
description: Reference nginx and fail2ban configuration for rate limiting a Pryv deployment, keyed on the routes that matter, with per-workload limits and a load test to prove the limits fire.
---


This page gives operators a reference **nginx + fail2ban** setup that throttles abusive traffic before it reaches Pryv: per-IP limits on the unauthenticated surfaces (login, registration, password reset, access requests), per-token limits on data reads and writes, connection caps, body size limits and slow-client timeouts, plus fail2ban jails that ban the source addresses.

Every number in it is a starting point. Read the [limits at a glance](#limits-at-a-glance) table for your workload, then [verify](#verify-the-limits-fire) that the limits fire before you rely on them.


## Why at the proxy

Pryv deliberately does not rate limit its API in-process. A per-core counter only sees its share of the traffic in a multi-core deployment, and what counts as abuse depends on the workload: a research consortium's batch import is a legitimate burst that a consumer app should never produce. The layer that sees all traffic before it is sharded, and that you already tune for your own traffic, is the reverse proxy. The full reasoning is in the compliance matrix context note on [rate limiting and DoS protection](https://github.com/pryv/compliance-matrix/blob/master/context/rate-limiting-and-dos-protection.md).

What Pryv **does** limit by itself, so you do not duplicate or contradict it:

| In-process limit | Where it applies | Configured by |
|---|---|---|
| Per-account backoff on failed second factors: after `freeFailures` (3) failures, each further failure delays the next attempt, doubling from 2 s to 300 s; answers `429 too-many-attempts` with `Retry-After` | MFA `verify`, `confirm`, `challenge` | `services.mfa.attempts` (see [MFA](/customer-resources/mfa/)) |
| Ceiling on pending access requests per core (10 000 by default, 16 KiB each); answers `429 too-many-requests` with `Retry-After: 60` | `POST /reg/access` | `access.maxLiveRequests`, `access.maxRequestBytes` |
| Per-address caps on sign-up email codes | `email-challenge` | see [Emails](/customer-resources/emails-setup/#at-registration-the-code-flow) |
| Request body size: JSON bodies, and each file of a multipart upload | every route | `uploads.maxSizeMb` (default 50) |

There is **no** in-process limit on password logins, on registration volume per caller, or on per-token request rates. Those are what this page covers.

Requests rejected by nginx never reach Pryv, so they appear in nginx's logs, not in Pryv's audit log or observability metrics. The nginx logs are therefore the record of a limit firing; keep them (see [logs are personal data](#logs-are-personal-data)).


## The routes that matter

A core serves user routes in one of two URL shapes, and the rules below match both:

- **Username in the path** (single core with `dnsLess.isActive: true`, the default, and DNSless multi-core where each core has its own `core.url`): `https://core.example.com/alice/events`.
- **Username in the host** (multi-core with embedded DNS, `dns.domain` set): `https://alice.example.com/events`. The core moves the subdomain into the path itself. Registration and access requests are then also reachable on the reserved hosts `reg.`, `access.` and `mfa.`, where the `/reg` prefix is implied (`https://reg.example.com/users`).

| Surface | Routes (path-style shown; host-style drops the `/{username}` prefix) | Caller | Key the limit on |
|---|---|---|---|
| Password login | `POST /{username}/auth/login` | unauthenticated | client IP |
| MFA second factor | `POST /{username}/mfa/challenge`, `/verify`, `/confirm`, `/recover` | MFA session token, or none (`recover`) | client IP (Pryv adds its per-account backoff) |
| Password reset | `POST /{username}/account/request-password-reset`, `/account/reset-password` | unauthenticated | client IP |
| Registration | `POST /users`, `POST /reg/users`, `POST /reg/user`, `POST /reg/email-challenge`, `POST /reg/email-challenge/verify` | unauthenticated | client IP |
| Lookups | `GET /reg/{username}/check_username`, `GET /reg/{email}/check_email`, `GET /reg/{email}/username`, `GET /reg/{email}/uid`, `GET /reg/{username}/server`, `GET /reg/cores`, `GET /reg/hostings`, `GET /reg/service/info` | unauthenticated | client IP (enumeration) |
| Access requests | `POST /reg/access` (create), `GET /reg/access/{key}` (polled by the app every second while pending), `POST /reg/access/{key}` (accept or refuse) | unauthenticated | client IP, creation stricter than polling |
| OAuth2 | `GET /oauth2/authorize`, `POST /oauth2/authorize/accept`, `/refuse`, `POST /oauth2/token` | unauthenticated / client credentials | client IP |
| SSO | `GET /auth/sso/providers`, `/auth/sso/{provider}/start`, `/callback` | unauthenticated | client IP |
| Data writes | `POST /{username}/events`, `PUT`/`POST`/`DELETE /{username}/events/{id}`, `POST /{username}/streams`, `POST /{username}/accesses`, batch calls `POST /{username}/` | access token | token |
| Data reads | `GET /{username}/events`, `GET /{username}/events/{id}`, `GET /{username}/streams`, ... | access token | token |
| Attachments | upload: multipart `POST /{username}/events` or `POST /{username}/events/{id}`; download: `GET /{username}/events/{id}/{fileId}[/{fileName}]` (token or `readToken`) | access token | token, plus body size |
| High-frequency series | `POST`/`GET /{username}/events/{id}/series`, `POST /{username}/series/batch` (served by the HFS worker, port 4000) | access token | token |
| Real-time | `/socket.io/` (WebSocket) | access token in the query | concurrent connections per IP |
| Admin | `/system/...`, `/reg/admin/...` | `adminAccessKey` | client IP, with your admin and core hosts exempt |

**How Pryv reads a token.** From the `Authorization` header (the bare token, `Bearer <token>`, or HTTP Basic with the token as user name), otherwise from the `auth` query parameter. The configuration below normalises the header the same way, so a token sent bare, as `Bearer`, with a trailing caller id, or as `?auth=` counts against one bucket. nginx cannot decode Basic credentials, so a token sent as HTTP Basic is keyed on its encoded form and gets a bucket of its own; that only matters for a client that mixes Basic with the other forms.

**How Pryv reads the client IP.** From the `X-Forwarded-For` request header only when the request comes from a proxy listed in `http.trustedProxies` (default `['loopback']`, which covers nginx on the same host), otherwise from the TCP peer. It records that value as the request source in the audit log. So:

- nginx must **overwrite** the forwarding headers with what it sees: `proxy_set_header X-Forwarded-For $remote_addr;`, `X-Forwarded-Host $http_host;` and `X-Forwarded-Proto $scheme;`. Do not use `$proxy_add_x_forwarded_for`, and do not pass a client's own `X-Forwarded-Host` through: coming from a trusted proxy, it would let that client pick the host a DPoP proof is checked against.
- nginx on another host, or reaching the core over a Docker bridge (Dokku's nginx arrives from `172.17.0.1`), must be listed in `http.trustedProxies`, or every request is recorded with nginx's address. See [INSTALL, client addresses behind a proxy](https://github.com/pryv/open-pryv.io/blob/master/INSTALL.md#client-addresses-behind-a-proxy-httptrustedproxies).
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

# Access-request creation is a POST; polling is a GET on the same prefix.
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
    # Pryv's own 429s (MFA backoff, access-request ceiling) pass through
    # untouched: proxy_intercept_errors is off.
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

    # ---------- Password login and MFA ----------
    # 10/min sustained plus a burst of 5: a user mistyping a password a few
    # times is never refused; a guessing script gets about 10 tries a minute.
    location ~ ^(?:/[^/]+)?/(?:auth/login|mfa/(?:challenge|verify|confirm|recover))$ {
        limit_req zone=pryv_login burst=5 nodelay;
        proxy_pass http://pryv_api;
    }

    # ---------- Password reset ----------
    location ~ ^(?:/[^/]+)?/account/(?:request-password-reset|reset-password)$ {
        limit_req zone=pryv_signup burst=3 nodelay;
        proxy_pass http://pryv_api;
    }

    # ---------- Registration and sign-up email codes ----------
    location ~ ^(?:/reg)?/(?:users?|email-challenge(?:/verify)?)$ {
        limit_req zone=pryv_signup burst=3 nodelay;
        proxy_pass http://pryv_api;
    }

    # ---------- Access requests ----------
    # Creation (POST) is held to 6/min with a burst of 5; every request on
    # this prefix, polling included, also counts against the polling zone.
    location ~ ^/reg/access(?:/|$) {
        limit_req zone=pryv_access_create burst=5 nodelay;
        limit_req zone=pryv_poll burst=10 nodelay;
        proxy_pass http://pryv_api;
    }

    # ---------- Admin routes ----------
    location ~ ^/(?:system|reg/admin)/ {
        limit_req zone=pryv_admin burst=20 nodelay;
        proxy_pass http://pryv_api;
    }

    # ---------- Other unauthenticated lookups ----------
    location ~ ^/reg/ {
        limit_req zone=pryv_lookup burst=20 nodelay;
        proxy_pass http://pryv_api;
    }

    # ---------- OAuth2 and SSO ----------
    location = /oauth2/token {
        limit_req zone=pryv_oauth_token burst=10 nodelay;
        proxy_pass http://pryv_api;
    }
    location ^~ /oauth2/authorize {
        limit_req zone=pryv_oauth_auth burst=30 nodelay;
        proxy_pass http://pryv_api;
    }
    location ^~ /auth/sso/ {
        limit_req zone=pryv_lookup burst=20 nodelay;
        proxy_pass http://pryv_api;
    }

    # ---------- High-frequency series (HFS worker) ----------
    # Host is the worker's own address. With usernames in the host (dns.domain
    # set), the HFS worker reads the first label of Host as a username, which
    # would break these path-style requests; in DNSless mode it is harmless.
    location ~ ^/[^/]+/(?:events/[^/]+/series|series/batch)(?:/|$) {
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
        # which keeps the timer fed.
        proxy_read_timeout 120s;
    }
}
```

### Username-in-host deployments

With `dns.domain` set, apps address `https://alice.example.com/...` and the paths carry no username. Three additions:

1. Add the user and reserved host names to `server_name` (`server_name example.com *.example.com;`) with a wildcard certificate.
2. On `reg.`, `access.` and `mfa.` the `/reg` prefix is implied, so the `/reg/...` locations above do not match there. Give those names their own server block that reuses the same zones:

   ```nginx
   server {
       listen 443 ssl;
       http2 on;
       server_name reg.example.com access.example.com mfa.example.com;
       # same ssl_*, access_log, error_log, client_* and proxy_set_header lines as above
       location ~ ^/(?:users?|email-challenge(?:/verify)?)$ { limit_req zone=pryv_signup burst=3 nodelay; proxy_pass http://pryv_api; }
       location ~ ^/access(?:/|$) {
           limit_req zone=pryv_access_create burst=5 nodelay;
           limit_req zone=pryv_poll burst=10 nodelay;
           proxy_pass http://pryv_api;
       }
       location ~ ^/admin/ { limit_req zone=pryv_admin burst=20 nodelay; proxy_pass http://pryv_api; }
       location / { limit_req zone=pryv_lookup burst=20 nodelay; proxy_pass http://pryv_api; }
   }
   ```

3. High-frequency series addressed on a user host (`/events/{id}/series`, `/series/batch`) do not match the HFS location above, which only routes the path-style form to the worker. They reach Pryv through `location /`, and the core forwards them to the HFS worker itself. To give them the HFS budget instead of the general one, add before `location /`:

   ```nginx
   location ~ ^/(?:events/[^/]+/series|series/batch)(?:/|$) {
       limit_req zone=pryv_hfs burst=20 nodelay;
       limit_req zone=pryv_ip burst=100 nodelay;
       proxy_pass http://pryv_api;   # keep Host: the username is in it
   }
   ```

### Multi-core deployments

The usual shape is one nginx per core, each with this configuration. Per-token limits stay exact: a token only works on its user's home core (other cores answer `421 wrong-core`), so all of a token's traffic meets the same nginx. The same holds for logins. Registration, lookups and access requests can be sent to any core, so a client spreading them over N cores gets N times the per-IP budget: divide those rates by the number of cores, or put a single edge in front of all cores so one counter sees everything.

Other proxies (HAProxy stick tables, Traefik or Caddy rate-limit middlewares, a CDN's rate-limiting rules) apply the same route table with the same keys.


## Composing with TLS

**nginx terminates TLS (the configuration above).** Pryv runs on plain HTTP (`http.port: 3000`, no `http.ssl` block). You can still let Pryv manage the certificate:

- Keep `letsEncrypt.enabled: true`. The renewer writes the certificate to `var-pryv/tls/<hostname>/fullchain.pem` and `privkey.pem` (under `letsEncrypt.tlsDir`); point `ssl_certificate` and `ssl_certificate_key` there, and set `letsEncrypt.onRotateScript` to a script running `nginx -t && nginx -s reload` (see [SSL certificate](/customer-resources/ssl-certificate/#strategy-a--built-in-auto-renewal-recommended)).
- With **DNS-01** (wildcard, username-in-host deployments) nothing else changes.
- With **HTTP-01** (single host name), Pryv answers the challenge on its own listener bound to port 80. nginx must then not listen on port 80: drop the redirect server block. Pryv's port-80 listener answers 404 to everything but the challenge, so plain-HTTP clients get no redirect to HTTPS. If you need that redirect, issue the certificate outside Pryv instead (certbot, or an ACME-capable proxy) and leave `letsEncrypt.enabled: false`.

**Pryv terminates TLS itself** (`http.port: 443` with `http.ssl`, often with the built-in renewer). An HTTP-aware proxy cannot sit in front without taking over TLS, because it cannot read paths or headers inside a connection it does not decrypt. Your options:

1. **Move TLS to nginx** (recommended). Switch Pryv to `http.ip: 127.0.0.1`, `http.port: 3000`, remove the `http.ssl` block, and follow the bullet points above to keep the built-in renewer. This is the only option that gives per-route and per-token limits.
2. **TCP passthrough** with nginx's `stream` module in front of port 443. nginx can then cap concurrent connections per IP (`limit_conn` in the `stream` context) and nothing else: no routes, no tokens, no 429. Worse, Pryv then sees nginx's address as the client of every request, in its audit log too; Pryv does not read the PROXY protocol. Use this only as a stopgap.
3. **No proxy.** You keep Pryv's in-process limits listed at the top, plus whatever the host firewall can do per IP at the connection level. Keep `http.trustedProxies` at its default: the core then ignores a client's own `X-Forwarded-For` and records the TCP peer. On cores before open-pryv.io 2.0.0-rc.36, any client could choose the IP recorded for its requests; there, treat the audit log's source IP as unverified.


## fail2ban

Three jails, all reading nginx's logs (Pryv's own logs are not involved). Install the filters, then the jail file, then `fail2ban-client reload`.

### Filters

```ini
# /etc/fail2ban/filter.d/pryv-auth-login-fail.conf
# Reads the nginx access log (log_format pryv).
# 401 = wrong password or wrong MFA code; 404 = unknown username (enumeration).
[Definition]
failregex = ^<HOST> - \[\] "POST (?:/[^/" ]+)?/auth/login HTTP/[\d.]+" (?:401|404) 
            ^<HOST> - \[\] "POST (?:/[^/" ]+)?/mfa/(?:verify|confirm|recover) HTTP/[\d.]+" 401 
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
failregex = ^<HOST> - \[\] "POST (?:/reg)?/access HTTP/[\d.]+" (?:201|429) 
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

If nginx runs in Docker with published ports, bans must go to the `DOCKER-USER` chain (for example `banaction = iptables-multiport` with `chain = DOCKER-USER`), or they never see the traffic.

Pryv's audit log also records the source IP of every audited API call, for your SIEM. fail2ban reads the nginx logs here because they cover requests that never reach Pryv, and failed logins for usernames that do not exist (which have no per-user audit log to write to).


## Logs are personal data

IP addresses in the nginx logs and the fail2ban database are personal data in most regimes. Rotate them on a schedule you have documented (`logrotate`, `dbpurgeage` in `fail2ban.conf`), and keep them in the same region as the core they protect when you operate cores under different data-residency rules. The log format above leaves query strings out so that tokens passed as `?auth=` never reach the access log; the error log still records the full request line of a refused request, so prefer the `Authorization` header in your apps.


## Limits at a glance

The configuration above is the consumer profile. Edit the `rate=` values in the zones and the `burst=` values in the locations for the others.

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

Trade-offs to keep in mind:

- **Shared addresses.** Mobile carriers put many subscribers behind one address (carrier-grade NAT), and hospitals put all staff behind a few. Per-IP limits and IP bans then hit everyone behind it. Keep per-IP limits for the unauthenticated surfaces, where there is nothing better to key on, and rely on per-token limits for data traffic. For known shared addresses, raise the limits through a `geo` map (as done for the admin zone) and list them in `ignoreip`.
- **IPv6.** `$binary_remote_addr` is a full /128 address and a single host usually controls a whole /64. If you see abuse rotating through one prefix, key the per-IP zones on the /64 instead (a `map` on `$remote_addr` keeping the first four groups).
- **Bursts versus rates.** The rate is what a client can sustain; the burst is how far ahead of it a client may go before refusals start. Batch importers need large bursts; login needs a small one. Too small a burst on read zones breaks apps that load a dashboard with a dozen parallel calls.


## Verify the limits fire

Test against a staging core, from an address you can afford to have banned (or add it to `ignoreip` while testing the limits, and remove it again to test the bans). The commands use [vegeta](https://github.com/tsenart/vegeta), a single binary with no account (`brew install vegeta`, or a release binary from GitHub), and `jq`.

**1. Login limit, per IP.** 5 attempts per second for 30 seconds against the `10r/m, burst 5` zone: about 10 requests are let through (the burst, plus 5 refills in 30 seconds) and get Pryv's `401`; the other 140 or so get `429` from nginx.

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

Run it a second time with `?auth=rate-limit-test-token` in the URL and no `Authorization` header: the counts must be the same, which proves the query-string token is keyed too.

**3. The jails.** Check each filter against the real logs, then watch a ban happen:

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
