---
title: 'Adapter routes'
description: Serve a sidecar container (an API facade, an agent gateway or any resource server for a core's accounts) under the core's own public URL, at /adapter/<name>/ on every host, without a reverse proxy in front.
---

An **adapter route** exposes a sidecar that runs on the same host as a core (typically a resource server for this core's accounts: an API facade, an agent gateway) under the core's own public URL, without an nginx in front. Available from open-pryv.io 2.0.0-rc.73.

```
https://<any host this core serves>/adapter/<name>/...         -> the sidecar
https://<any host>/.well-known/<label>/adapter/<name>/...       -> the sidecar (optional prefixes)
everything else                                                 -> the core, as before
```

:::caution[The core forwards unauthenticated traffic]
On adapter paths the core applies none of its own authentication, CORS, audit or rate limiting. The sidecar is a resource server: it answers its own `401` + `WWW-Authenticate` challenges, validates the tokens it receives (for instance through [token exchange](/customer-resources/auth-oauth2/#token-exchange-for-resource-servers) or introspection with its own registry client), answers its own CORS (preflights included) and audits what it does. Never publish the sidecar's port to the internet: everything must reach it through the core.
:::

## Configuration

Per core, in the override configuration (`adapterRoutes: {}` by default: the feature is off):

```yaml
adapterRoutes:
  calendar:                                   # the route name: a DNS label, not "adapter"
    upstream: http://172.17.0.1:7450          # required: the sidecar's origin (scheme, host, port)
    paths:                                    # optional; /adapter/<name>/ is always included
      - /adapter/calendar/
      - /.well-known/oauth-protected-resource/adapter/calendar/
    maxBodyBytes: 1048576                     # optional; larger request bodies answer 413 (default 1 MiB)
    idleTimeoutMs: 60000                      # optional; 504 when no byte moves for this long (default 60 s)
```

| Key | Rule |
|---|---|
| name | a DNS label (1-63 lowercase letters, digits, inner hyphens); `adapter` is refused |
| `upstream` | an absolute `http:` or `https:` origin, no path, query or credentials; never a host of this platform nor this core's own listener. `http:` to an address that is not loopback, private, link-local or a container name warns at boot (the traffic, credentials included, travels in clear) |
| `paths` | each entry starts with `/adapter/<name>/` or `/.well-known/<label>/adapter/<name>/` and ends with `/`; the core's own `.well-known` documents (`oauth-authorization-server`, `openid-configuration`, `acme-challenge`) are refused |
| `maxBodyBytes` | positive integer, bytes |
| `idleTimeoutMs` | positive integer, milliseconds, at most 24 h; below 5 s warns |

Unknown keys are refused. `bin/check-config.js` and the boot validation report every problem with its key path. Keep the route names and `paths` identical on every core of a platform (the same adapter at the same URL on each); `upstream` is per core.

**Reserved username.** `adapter` cannot be registered nor taken by a rename. A core with at least one route **refuses to boot while an account named `adapter` exists**: rename that account first (`account.changeUsername`). A backup that names an account `adapter` is refused at restore. In dnsLess mode, a hosted site cannot be named `adapter`.

At boot each route logs one line (`adapter route <name>: <upstream> paths <list>`). There is no probe of the upstream: a sidecar may start after the core.

## What is forwarded

Matching is on the path only, on every host the core serves, before hosted sites, HF series, previews and the API. The path is normalised first (dot segments resolved); the query is forwarded unchanged.

- **Request:** every method but TRACE (preflight `OPTIONS` included), the body (streamed), every header except the hop-by-hop ones and `Expect`. `Authorization`, `Cookie`, `DPoP` and `Origin` pass. `Host` is kept as the client sent it. The core sets `X-Forwarded-For`, `X-Forwarded-Proto` and `X-Forwarded-Host` (replacing the client's values, except those of a trusted proxy in front, see `http.trustedProxies`).
- **Response:** status and every header except the hop-by-hop ones (`WWW-Authenticate`, `Set-Cookie`, `Location`, `Access-Control-*` included), streamed. The core adds no header of its own.
- **Not supported:** WebSocket upgrades. Server-sent events and streamed HTTP responses work, as long as bytes move more often than `idleTimeoutMs`.

## Per-user addresses and the addressed account

From open-pryv.io 2.0.0-rc.75, on a platform with per-user hosts, an adapter is addressed by **username**, never by core: `https://<username>.<dns.domain>/adapter/<name>/...`. The DNS sends that host to the account's core. A host names an account only when it is exactly one label under `dns.domain`, that label has the shape of a username, is not `adapter` and is not a name the platform answers itself (a service host, a core id, a hosted site, a static or runtime DNS entry). Every other host is a **platform address**: a service or core host, a host under any other domain, every host of a dnsLess core or of a core without `dns.domain`.

On a per-user host the core:

1. **Answers `421 wrong-core`** when the platform serves the account from another core (a resolver still holding an earlier DNS answer, a hosts entry, a pinned proxy), for every method, without contacting the sidecar and never with a redirect. The answer carries `Retry-After` (`dns.defaultTTL`, 300 s by default) and `coreUrl`. **The client retries the same address**; `coreUrl` says which core should be answering and is not an address to call (`coreUrl` + the path is a platform address: no account is named there). The answer has no CORS header, like every answer of the core on adapter paths: a browser client sees a network error and retries later.
2. **Forwards a name the platform does not map** like a local one (the sidecar's own authentication refuses a stranger).
3. **Names the account to the sidecar** with two headers, set by the core only. Client-sent copies, in any `-` / `_` spelling, are dropped on every adapter request, a trusted proxy's included.

| Header | Value | Example |
|---|---|---|
| `X-Adapter-Name` | the addressed name, lowercased | `alice` |
| `X-Adapter-Base` | the route's base as the client addressed it: forwarded scheme, host lowercased with its port and without a final dot, the route root `/adapter/<name>/` | `https://alice.example.com/adapter/calendar/` |

Both are absent on a platform address. **They are an address, not an identity:** the core authenticates nothing on these paths, the token is the identity. What the sidecar does with them:

- its public URLs, its RFC 9728 `resource` and the links it emits are `X-Adapter-Base` + its own path, and its audience check is `aud === X-Adapter-Base + <its resource path>`;
- "is this request addressed to an account" is "is `X-Adapter-Name` there"; at a platform address it serves what needs no account, a platform-level resource if it has one, or `404`;
- it never derives an account from `Host`, never keeps a core map, never calls `/reg/<username>/server`; after an account moves its address is unchanged: on a `421` or a `503`, retry the same address after `Retry-After`;
- it accepts the two headers from the core only;
- **upgrade each core before the sidecar next to it starts reading the two headers**: a core of an earlier release forwards client-sent copies.

Callers that hold a username build the address from `/service/info`: `api` with `{username}` filled plus `adapter/<name>/`, or an entry of `adapters`, which the core passes through as the operator sets it in `service.adapters` (use the template form, `https://{username}.example.com/adapter/calendar/`).

## Answers of the core

| Status | When |
|---|---|
| 400 | an encoded `/`, `\`, `%00` or dot segment in the path, an invalid percent-encoding, or a `Transfer-Encoding` other than `chunked` |
| 405 | TRACE |
| 413 | the body is above `maxBodyBytes` (a declared length is refused before the sidecar is contacted) |
| 421 | the request is addressed to an account another core serves (see [per-user addresses](#per-user-addresses-and-the-addressed-account)), with `Retry-After` |
| 500 | the request is addressed to an account and the platform cannot say where it lives: not forwarded on a guess |
| 502 | the sidecar cannot be reached |
| 504 | no byte moved for `idleTimeoutMs` before the sidecar answered |

The body is JSON (`{ "error": { "id", "message" } }`) and never names the upstream address.

## Example: a sidecar container next to the core

```bash
docker network create pryv
docker run -d --name calendar --network pryv <sidecar image>     # listens on 7450, no -p
docker run -d --name pryvio --network pryv -p 443:443 -p 80:80 \
  -v /host/pryv/override-config.yml:/app/config/override-config.yml:ro \
  pryvio/open-pryv.io:<version>
```

```yaml
adapterRoutes:
  calendar:
    upstream: http://calendar:7450
    paths: ['/adapter/calendar/', '/.well-known/oauth-protected-resource/adapter/calendar/']
```

The sidecar's public base URL is `https://<core host>/adapter/calendar/` at a platform address, and `X-Adapter-Base` on a request addressed to an account (`https://alice.<domain>/adapter/calendar/`). Configure the platform one in the sidecar. A resource server must: its `resource` is a published, audience-bound value. An adapter whose links bind no account (a feed whose URL carries its own credentials) may instead build the link from `X-Forwarded-Proto` and `Host`, which the core forwards, as the request's origin and never as an account. Without a shared network, bind the sidecar to the Docker bridge gateway (`-p 172.17.0.1:7450:7450`) and use `upstream: http://172.17.0.1:7450`.

## Behind nginx

nginx can route the same prefixes straight to the sidecar, or leave them to the core, which then forwards them itself, keeping the `X-Forwarded-*` values of the trusted nginx. Raise nginx's `client_max_body_size` to the route's `maxBodyBytes` if above 1 MiB.

**Routing around the core drops the per-user triage.** Behind an nginx that sends `/adapter/` straight to the sidecar, the core never sees the request: no `421` for an account of another core, no `X-Adapter-Name` / `X-Adapter-Base`. Choose one: (a) let the core forward adapter paths: the per-user triage and the two headers work; or (b) keep the bypass: every request through it is then a platform address, a per-user host included. The sidecar must not derive the account from `Host` itself: which labels name an account is the platform's knowledge (its domain, the service names, the core ids, hosted sites, static and runtime DNS entries, and where each account lives), and a value the sidecar derived without it would end up in its public URLs and audience checks. nginx cannot set the two headers either; with (b), have nginx clear them (`proxy_set_header X-Adapter-Name "";` and the same for `X-Adapter-Base`) and expect per-user addresses to work only through (a).

## Troubleshooting

- **502 `adapter <name> unreachable`:** the sidecar is down or not reachable from the core's container (wrong network, bound to `127.0.0.1` inside its own container).
- **504 `adapter <name> timed out`:** raise `idleTimeoutMs`, or have long streams send keep-alive comments.
- **413:** raise `maxBodyBytes` for that route (and nginx's `client_max_body_size` if one is in front).
- **The core refuses to boot: "a user named adapter exists":** rename that account, then restart.
- **A browser app gets a CORS error:** the sidecar must answer the preflight and send `Access-Control-Allow-Origin` itself.
- **421 `wrong-core` on a per-user address:** the address is right; the request reached the wrong core (a stale resolver, a hosts entry, a pinned proxy). Retry the same URL after `Retry-After`; `coreUrl` tells the operator which core should be answering.
- **The sidecar never sees `X-Adapter-Name`:** the host is a platform address (a service or core host, a host not under `dns.domain`, a dnsLess core, `dns.domain` unset), or an nginx routes `/adapter/` around the core (see [Behind nginx](#behind-nginx)).

The full operator reference is open-pryv.io [`docs/adapter-routes.md`](https://github.com/pryv/open-pryv.io/blob/master/docs/adapter-routes.md).
