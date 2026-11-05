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

## Answers of the core

| Status | When |
|---|---|
| 400 | an encoded `/`, `\`, `%00` or dot segment in the path, an invalid percent-encoding, or a `Transfer-Encoding` other than `chunked` |
| 405 | TRACE |
| 413 | the body is above `maxBodyBytes` (a declared length is refused before the sidecar is contacted) |
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

The sidecar's public base URL is `https://<core host>/adapter/calendar/`. Without a shared network, bind the sidecar to the Docker bridge gateway (`-p 172.17.0.1:7450:7450`) and use `upstream: http://172.17.0.1:7450`. Behind nginx, either route the same prefixes to the sidecar there or leave them to the core.

## Troubleshooting

- **502 `adapter <name> unreachable`:** the sidecar is down or not reachable from the core's container (wrong network, bound to `127.0.0.1` inside its own container).
- **504 `adapter <name> timed out`:** raise `idleTimeoutMs`, or have long streams send keep-alive comments.
- **413:** raise `maxBodyBytes` for that route (and nginx's `client_max_body_size` if one is in front).
- **The core refuses to boot: "a user named adapter exists":** rename that account, then restart.
- **A browser app gets a CORS error:** the sidecar must answer the preflight and send `Access-Control-Allow-Origin` itself.

The full operator reference is open-pryv.io [`docs/adapter-routes.md`](https://github.com/pryv/open-pryv.io/blob/master/docs/adapter-routes.md).
