---
title: 'Pryv.io core migration'
description: "How to migrate a Pryv.io v2 core to a new machine: copy config and data, start the core on the destination host, and cut over DNS without downtime."
---


This guide describes how to migrate a Pryv.io **core** to a new machine — that is, moving the running core binary, its configuration and its persistent data to a fresh host while keeping the same public URL.

> **Since v2 (2026)** Pryv.io runs as a **single binary** (`bin/master.js`) in a **single Docker image** (`pryvio/open-pryv.io`). Moving a core is therefore a single-service migration: copy the config, copy the data directories (plus your database dump), start the core on the new host, and either point DNS or proxy traffic from the old host while DNS propagates. There is no longer a separate `register`, `hfs`, `preview` or `mfa` container to coordinate.

The strategy:

1. Install the core on the **dest** machine
2. Copy config and data from **source** to **dest**
3. Bring the core up on **dest**
4. Either update DNS to point to **dest**, or keep **source** alive as an NGINX proxy to **dest** during DNS propagation
5. Stop **source** once traffic has drained

## (Optional) Create a verification user on source

Create a test user with a few streams and events on the **source** core before the migration. After the cutover, log in as that user on **dest** and check that the data is intact — a quick naked-eye check complements the automated verification steps later.


## Set up the dest machine

On **dest**, install the same core version as **source**:

- Either pull the Docker image (same tag as on source: `docker pull pryvio/open-pryv.io:<tag>`)
- Or clone the same commit and run `just setup-dev-env && just install` (native install)

Also install the database you use (PostgreSQL or MongoDB), unless you are running the database on a separate host that will remain unchanged.

Set up an SSH key pair for rsync:

```bash
ssh-keygen -t rsa -b 4096 -C "migration@remote"
# private key stays on source at ${PATH_TO_PRIVATE_KEY}
# public key goes into ~/.ssh/authorized_keys on dest
```


## Transfer data

### Transfer configuration

Copy the override YAML(s) used on **source**. Their path depends on how you run the core. Typical locations:

- Docker deploy: the mounted config volume (e.g. `/etc/pryv/override.yml`)
- Native deploy: the file passed via `--config` to `bin/master.js`
- Dokku deploy: the app config stored under `/home/dokku/<app>/`

```bash
# on source
rsync --verbose --copy-links --archive --compress \
    -e "ssh -i ${PATH_TO_PRIVATE_KEY}" \
    /etc/pryv/ \
    ${USERNAME}@${DEST_MACHINE}:/etc/pryv/
```

If the machine's IP, private network or database host changes as part of the migration, edit the override YAML on **dest** accordingly (for example `storages.engines.postgresql.host` or `core.ip`).

### Dump and transfer the database

Stop the core on **source** before dumping, so the dump is consistent and no writes come in during the transfer:

```bash
# Docker: docker stop pryvio_open_pryv_io
# Systemd: systemctl stop pryv-core
```

**PostgreSQL** (recommended):

```bash
# on source (or on your PG host)
pg_dump -U postgres -Fc pryv_db > /tmp/pryv_db.dump
rsync -e "ssh -i ${PATH_TO_PRIVATE_KEY}" \
    /tmp/pryv_db.dump \
    ${USERNAME}@${DEST_MACHINE}:/tmp/pryv_db.dump

# on dest (restore into an empty database)
createdb -U postgres pryv_db
pg_restore -U postgres -d pryv_db /tmp/pryv_db.dump
```

**MongoDB**:

```bash
# on source
mongodump --db=pryv-node --out=/tmp/mongodump
rsync --archive --compress \
    -e "ssh -i ${PATH_TO_PRIVATE_KEY}" \
    /tmp/mongodump/ \
    ${USERNAME}@${DEST_MACHINE}:/tmp/mongodump/

# on dest
mongorestore /tmp/mongodump/
```

**InfluxDB** (optional — only if you use InfluxDB for high-frequency series; PostgreSQL is fine too and moves with the PG dump above):

```bash
# on source
influxd backup -portable /tmp/influx-backup

# on dest (after rsync)
influxd restore -portable /tmp/influx-backup
```

### Transfer file-system data

Per-user SQLite DBs, attachments, previews and the rqlite platform DB all live under the core's `data/` directory (see [INSTALL — Data directories](https://github.com/pryv/open-pryv.io/blob/master/INSTALL.md#data-directories)). Transfer the whole tree:

```bash
# on source — adjust paths to match your filesystem and sqlite.path config
rsync --verbose --copy-links --archive --compress \
    -e "ssh -i ${PATH_TO_PRIVATE_KEY}" \
    /var/lib/pryv/data/ \
    ${USERNAME}@${DEST_MACHINE}:/var/lib/pryv/data/
```

Ensure file ownership on **dest** matches the UID the core runs as (root for the stock Docker image; the `pryv` user for native installs).


## Launch the core on dest

Start the core:

```bash
# Docker
docker start pryvio_open_pryv_io

# Native / systemd
systemctl start pryv-core
```

Watch the logs for a clean startup — `master.js` should report its workers ready, rqlited up, and HTTP listeners bound:

```bash
docker logs -f pryvio_open_pryv_io
# or
journalctl -u pryv-core -f
```

Do **not** start the core on **dest** while **source** is still serving traffic with the same database — both cores writing to the same base storage will corrupt data.


## Cut over

### Option A — update DNS and stop source

Simplest path when you can schedule a short outage:

1. Keep **source** stopped after the dump.
2. Start the core on **dest**.
3. Update the DNS A record for the public domain to the new IP.
4. Wait for propagation. Clients that still hit the old IP while DNS is stale will fail; this is the outage window.

### Option B — proxy from source to dest during DNS propagation

Zero-downtime variant: keep **source**'s reverse proxy alive and point it at **dest** until DNS propagates, then retire **source**.

In v2 the core exposes just two HTTP upstreams — API on port 3000 and HFS on port 4000 (see [INSTALL — Running behind nginx](https://github.com/pryv/open-pryv.io/blob/master/INSTALL.md#running--behind-nginx)). Replace the `api_backend` / `hfs_backend` upstreams in **source**'s NGINX:

```nginx
# on source — was pointing at localhost
upstream api_backend { server 127.0.0.1:3000; }
upstream hfs_backend { server 127.0.0.1:4000; }

# becomes (TLS-terminated by dest, plain https upstream)
upstream api_backend { server ${DEST_CORE_IP}:443; }
upstream hfs_backend { server ${DEST_CORE_IP}:443; }
```

and change every `proxy_pass http://api_backend` / `http://hfs_backend` to `https://api_backend` / `https://hfs_backend`.

Reload NGINX on **source**. All traffic now flows `client → source NGINX → dest`. When DNS has propagated (monitor **source**'s access log until it goes idle), stop NGINX on **source** and decommission the host.


## Verify

Once traffic is landing on **dest**:

- Log in as the verification user from the pre-migration step and spot-check recent events.
- Watch the core logs to confirm that API calls arrive on **dest** and not on **source**.
- Hit the basic endpoints described in the [healthchecks guide](/customer-resources/healthchecks/).


## Multi-core deployments — update the PlatformDB entry

In **v2 multi-core** mode each core self-registers into the rqlite PlatformDB on startup with its `core.id`, `core.ip`, `core.available` and (for DNSless multi-core) `core.url`. Restarting the moved core on **dest** automatically re-advertises the new IP/URL — **there is no register machine or admin panel to edit**.

Two things to check after the move:

1. **`core.id` is unchanged** — the ID identifies this core's user partition in the platform. Keep it the same on **dest** so existing user→core mappings stay valid.
2. **Other cores can reach the new host** — the Raft port (default 4002) must be open between all cores. From another core:

   ```bash
   curl -s https://core-x.mc.example.com/system/admin/cores -H 'Authorization: <admin-key>'
   ```

   The moved core should appear in the list with its new IP.

If you run **v1** and still need to update the old register machine's `HOSTINGS_AND_CORES` entry, see the [v1 register migration reference](/customer-resources/register-migration/) for the legacy procedure.
