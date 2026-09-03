---
title: 'Pryv.io Healthchecks'
---


This guide describes how to perform regular healthcheck API calls against a Pryv.io deployment in order to monitor its status remotely.

> **Since v2 (2026)** Pryv.io runs as a single binary; there is no longer a DNS / register / core split. All the checks below hit one and the same service. In **multi-core** mode, each core exposes the same endpoints — run the checks per core to detect a single faulty instance.

The checks in this guide require a dedicated healthcheck user account with a non-expirable access token. Create it once and reuse the `(username, token)` pair in your monitoring system.


## Table of contents <!-- omit in toc -->

1. [Variables](#variables)
2. [Tools](#tools)
3. [Preparation — create the healthcheck account](#preparation--create-the-healthcheck-account)
   1. [Create the user](#create-the-user)
   2. [Obtain a non-expirable access token](#obtain-a-non-expirable-access-token)
4. [Healthchecks](#healthchecks)
   1. [1. DNS resolution (multi-core only)](#1-dns-resolution-multi-core-only)
   2. [2. Registration endpoint reachable](#2-registration-endpoint-reachable)
   3. [3. Core API + base storage reachable](#3-core-api--base-storage-reachable)
   4. [4. (Optional) HFS port reachable](#4-optional-hfs-port-reachable)


## Variables

Replace the following variables in the commands below:

- `${DOMAIN}` — the public domain. In a single-core `dnsLess` deployment this is the whole public URL's host (e.g. `api.example.com`). In multi-core mode it's the shared domain used for user subdomains (e.g. `mc.example.com`).
- `${USER}` — the healthcheck username (recommendation: `healthmetrics01`).
- `${ACCESS_TOKEN}` — a non-expirable access token for `${USER}`, obtained in the preparation section.
- `${USER_URL}` — the full base URL for user API calls:
  - single-core / dnsLess: `https://${DOMAIN}/${USER}` (path-based)
  - multi-core: `https://${USER}.${DOMAIN}` (subdomain-based)
- `${REG_URL}` — the base URL for registration endpoints:
  - single-core / dnsLess: `https://${DOMAIN}/reg`
  - multi-core: any core's URL, e.g. `https://core-a.${DOMAIN}/reg`


## Tools

- `dig` v9.12+ (multi-core DNS check only)
- `curl` v7.54+


## Preparation — create the healthcheck account

### Create the user

Registration endpoint is the same in both topologies — just pick the right `${REG_URL}`:

```bash
curl -i -X POST -H 'Content-Type: application/json' \
    -d '{"appId":"pryv-metrics",
         "username":"healthmetrics01",
         "password":"healthmetrics01",
         "email":"healthmetrics01@example.com",
         "languageCode":"en"}' \
    "${REG_URL}/users"
```

If you enabled registration invitation tokens (`services.register.invitationTokens`), add `"invitationtoken":"..."` to the body.

Alternatively, use the registration page of your deployed auth web app ([app-web-user-account](https://github.com/pryv/app-web-user-account)) — e.g. `https://${DOMAIN}/access/register` if you proxy `/access/` to it as shown in the [pages customization FAQ](/faq-infra/#customize-registration-login-password-reset-pages); the base URL is whatever you set `access.defaultAuthUrl` to.

### Obtain a non-expirable access token

Two calls: sign in with the password to get a personal token, then use it to create a shared access token.

**Sign in:**

```bash
curl -i -H "Content-Type: application/json" \
    -X POST \
    -d '{"username":"healthmetrics01",
         "password":"healthmetrics01",
         "appId":"pryv-metrics"}' \
    "${USER_URL}/auth/login"
# → { "token": "${PERSONAL_TOKEN}", ... }
```

**Create the shared access:**

```bash
curl -i -X POST -H 'Content-Type: application/json' \
    -H 'Authorization: ${PERSONAL_TOKEN}' \
    -d '{"name":"metricsAccess",
         "permissions":[{"streamId":"*","level":"manage"}]}' \
    "${USER_URL}/accesses"
# → { "access": { "token": "${ACCESS_TOKEN}", ... } }
```

Store `${ACCESS_TOKEN}` in your monitoring system's secret store.


## Healthchecks

### 1. DNS resolution (multi-core only)

Skip this section in single-core `dnsLess` mode (no user subdomains).

```bash
dig A healthmetrics01.${DOMAIN}
```

**Expected:** an `ANSWER SECTION` with an A record pointing at one of the core IPs.

### 2. Registration endpoint reachable

Uses the registration subsystem and (transitively) the rqlite platform DB:

```bash
curl -i "${REG_URL}/healthmetrics01/check_username"
```

**Expected:** `HTTP/1.1 200 OK` with a JSON body reporting whether the username is taken.

### 3. Core API + base storage reachable

Uses authentication, base storage (PostgreSQL / MongoDB) and event retrieval:

```bash
curl -i -H 'Authorization: ${ACCESS_TOKEN}' \
    "${USER_URL}/events?limit=1"
```

**Expected:** `HTTP/1.1 200 OK` with a JSON `events` array (possibly empty if you haven't written any).

### 4. (Optional) HFS port reachable

Only relevant if your deployment exposes the high-frequency series endpoints. HFS listens on port 4000; your reverse proxy should forward `/{user}/events/{id}/series` to it. A cheap check is the OPTIONS response on the series route:

```bash
curl -i -X OPTIONS -H 'Authorization: ${ACCESS_TOKEN}' \
    "${USER_URL}/events/nonexistent/series"
```

**Expected:** `HTTP/1.1 2xx` or a documented 4xx from the HFS stack (a 502/504 would indicate the HFS worker is down or unreachable from the proxy). See [INSTALL — HFS Host header](https://github.com/pryv/open-pryv.io/blob/master/INSTALL.md#important-nginx-notes) for the one NGINX pitfall to watch out for.


If you need per-worker or per-process checks, get in touch with your Pryv tech contact — there is currently no public per-worker status endpoint.
