---
title: 'Quickstart: Docker, DNS-less, HTTP-only'
description: Boot a single-core Pryv.io on one host with Docker, no DNS and no TLS, using a Postgres sidecar and a complete override-config template.
---

This walkthrough boots a **single-core Pryv.io** on one host with **Docker**, **no DNS**
(`dnsLess`) and **plain HTTP** (no Let's Encrypt). It is the fastest way to try the API
end to end. It is not a production setup: for that, add TLS, a real domain and the
regular multi-core configuration described in the rest of the setup documentation.

## Before you start

- A host with Docker installed and a shell.
- Ports `3000` (API) free on the host.
- No TLS certificate and no DNS zone are required in this mode.

Three things trip people up in this mode, so they are handled explicitly below:

1. **Config does not expand environment-variable placeholders.** Use literal paths in
   your `override-config.yml`; do not rely on `${...}` substitution.
2. **The image does not bundle PostgreSQL.** Pryv.io stores user data in PostgreSQL, so
   you run a Postgres container alongside it (a "sidecar").
3. **Every storage path must be set.** The SQLite, filesystem and rqlite paths have no
   usable defaults; the template below sets all of them.

## 1. Create a network

```bash
docker network create pryv-net
```

## 2. Start a PostgreSQL sidecar

```bash
docker run -d --name pryv-pg --network pryv-net \
  -e POSTGRES_DB=pryv-node \
  -e POSTGRES_USER=pryv \
  -e POSTGRES_PASSWORD=pryv-secret \
  postgres:16
```

## 3. Write `override-config.yml`

Generate two random secrets and drop them into the template. Replace
`http://YOUR_HOST:3000` with the URL the API will be reached at (for a local trial,
`http://localhost:3000` works).

```bash
mkdir -p ./pryv/data/{attachments,previews,users,logs} ./pryv/rqlite-data
ADMIN_KEY=$(openssl rand -hex 16)
FILES_SECRET=$(openssl rand -hex 16)
```

```yaml
# override-config.yml
auth:
  adminAccessKey: REPLACE_WITH_ADMIN_KEY
  filesReadTokenSecret: REPLACE_WITH_FILES_SECRET
  trustedApps: '*@*'

cluster:
  apiWorkers: 1
  hfsWorkers: 0
  previewsWorker: false

dnsLess:
  isActive: true
  publicUrl: http://YOUR_HOST:3000

http:
  ip: 0.0.0.0
  port: 3000

service:
  name: 'Pryv.io QuickStart'
  eventTypes: https://pryv.github.io/event-types/flat.json
  home: http://YOUR_HOST:3000
  support: http://YOUR_HOST:3000
  terms: http://YOUR_HOST:3000

services:
  email:
    enabled:
      welcome: false
      resetPassword: false

logs:
  file:
    active: true
    level: info
    path: /app/data/logs/api-server.log

storages:
  engines:
    postgresql:
      host: pryv-pg
      port: 5432
      database: pryv-node
      user: pryv
      password: pryv-secret
      max: 20
    filesystem:
      attachmentsDirPath: /app/data/attachments
      previewsDirPath: /app/data/previews
    sqlite:
      path: /app/data/users
    rqlite:
      url: http://127.0.0.1:4001
      raftPort: 4002
      dataDir: /app/var-pryv/rqlite-data
```

Keep `override-config.yml` readable only by you (`chmod 600 override-config.yml`) and
rotate `adminAccessKey` before exposing the host.

## 4. Run Pryv.io

Pick the current release tag for `pryvio/open-pryv.io` and bind-mount the config and data
directories:

```bash
docker run -d --name pryv-quickstart --network pryv-net \
  -v $(pwd)/pryv/data:/app/data \
  -v $(pwd)/pryv/rqlite-data:/app/var-pryv/rqlite-data \
  -v $(pwd)/override-config.yml:/app/config/override-config.yml:ro \
  -e NODE_ENV=production \
  -p 3000:3000 \
  pryvio/open-pryv.io:latest
```

## 5. Verify

The service descriptor should answer:

```bash
curl -sS http://YOUR_HOST:3000/reg/service/info
```

Create a user and receive its API endpoint:

```bash
curl -sS -X POST http://YOUR_HOST:3000/reg/users \
  -H 'Content-Type: application/json' \
  -d '{"username":"alice","password":"secretpassword","email":"alice@example.com","appId":"pryv-quickstart"}'
```

From here, follow [Get started](/getting-started/) to make your first authenticated API
calls, and the [API reference](/reference/) for the full surface.

## Using docker compose

The same setup as a single `docker-compose.yml`:

```yaml
services:
  pryv-pg:
    image: postgres:16
    environment:
      POSTGRES_DB: pryv-node
      POSTGRES_USER: pryv
      POSTGRES_PASSWORD: pryv-secret
    networks: [pryv-net]

  pryv:
    image: pryvio/open-pryv.io:latest
    depends_on: [pryv-pg]
    environment:
      NODE_ENV: production
    ports:
      - '3000:3000'
    volumes:
      - ./pryv/data:/app/data
      - ./pryv/rqlite-data:/app/var-pryv/rqlite-data
      - ./override-config.yml:/app/config/override-config.yml:ro
    networks: [pryv-net]

networks:
  pryv-net:
```
