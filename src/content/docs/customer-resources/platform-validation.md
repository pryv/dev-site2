---
title: 'Pryv.io platform validation guide'
---


This guide describes how to validate that a Pryv.io platform is up and running after install or after an upgrade.

> **Since v2 (2026)** Pryv.io is a single binary serving registration, core API, HFS and — in multi-core mode — DNS. Validation is therefore one short checklist instead of four (DNS + register + core + NGINX). In multi-core mode, run the checklist against every core.


## Table of contents <!-- omit in toc -->

1. [Variables](#variables)
2. [Tools](#tools)
3. [Checklist](#checklist)
   1. [1. Process is up](#1-process-is-up)
   2. [2. Public URL responds](#2-public-url-responds)
   3. [3. Registration / rqlite reachable](#3-registration--rqlite-reachable)
   4. [4. DNS (multi-core only)](#4-dns-multi-core-only)
   5. [5. Base storage (PostgreSQL / MongoDB) reachable](#5-base-storage-postgresql--mongodb-reachable)
   6. [6. (Optional) HFS port reachable](#6-optional-hfs-port-reachable)
   7. [7. mTLS handshake on Raft (multi-core only)](#7-mtls-handshake-on-raft-multi-core-only)
4. [Troubleshoot](#troubleshoot)
   1. [Core does not start](#core-does-not-start)
   2. [502 / 504 from the reverse proxy](#502--504-from-the-reverse-proxy)
   3. [rqlite cluster split-brain or not converging](#rqlite-cluster-split-brain-or-not-converging)
   4. [DNS does not resolve user subdomains](#dns-does-not-resolve-user-subdomains)
   5. [Base storage connection fails](#base-storage-connection-fails)
   6. [Permission denied on data directories](#permission-denied-on-data-directories)


## Variables

Replace these placeholders:

- `${DOMAIN}` — the public domain (path-based in `dnsLess`, subdomain base in multi-core).
- `${PUBLIC_URL}` — the full public URL of the core (`dnsLess.publicUrl` or `https://core-a.${DOMAIN}`).
- `${CORE_HOST}` — hostname the core runs on (SSH target for log inspection).
- `${DATA_DIR}` — data root from your config (see [INSTALL — Data directories](https://github.com/pryv/open-pryv.io/blob/master/INSTALL.md#data-directories)).


## Tools

- `curl` v7.54+
- `dig` v9.12+ (multi-core only)
- SSH access to each core machine


## Checklist

### 1. Process is up

- Docker: `docker ps` should list `pryvio_open_pryv_io` (or your container name) in an `Up` state.
- systemd: `systemctl status pryv-core` should show `active (running)`.
- Logs should end with the API/HFS workers signalling readiness — no restart loop.

### 2. Public URL responds

```bash
curl -i ${PUBLIC_URL}/reg/service/info
```

**Expected:** HTTP 200 with a JSON body listing `api`, `register`, `access`, `name`, `version`.

**Common failures:**
- `Could not resolve host` → DNS or hosts-file not pointing at the core.
- `Connection refused` → the core or the reverse proxy is not listening on 443.
- `502 Bad Gateway` → the reverse proxy can't reach the core on port 3000.

### 3. Registration / rqlite reachable

Forces a round-trip through the rqlite platform DB:

```bash
curl -i ${PUBLIC_URL}/reg/testuser/check_username
```

**Expected:** HTTP 200 with a JSON body telling you whether `testuser` is reserved.

If this returns 500, inspect the core logs for rqlited errors — see the [rqlite troubleshooting](#rqlite-cluster-split-brain-or-not-converging) section.

### 4. DNS (multi-core only)

Skip in `dnsLess` mode.

Verify that your domain's nameservers point to the cores:

```bash
dig NS +trace +nodnssec ${DOMAIN}
```

The last hop should return NS records that resolve to your core IPs. Then confirm a user subdomain resolves (use any registered username, or create one first):

```bash
dig A someuser.${DOMAIN}
```

**Expected:** an `ANSWER SECTION` with an A record for one of the cores.

### 5. Base storage (PostgreSQL / MongoDB) reachable

The core logs a fatal error and exits if it cannot connect to its base storage on startup — step 1 catches this. To double-check the connection independently:

- PostgreSQL: `psql -h <host> -U <user> -d pryv_db -c '\dt'` from the core machine.
- MongoDB: `mongosh --host <host> --eval 'db.stats()' pryv-node` from the core machine.

### 6. (Optional) HFS port reachable

Only if your deployment uses HFS (high-frequency series):

```bash
curl -i -X OPTIONS ${PUBLIC_URL}/someuser/events/abc/series
```

**Expected:** a 2xx or a documented 4xx from the HFS stack. A 502/504 means the reverse proxy can't reach port 4000.

### 7. mTLS handshake on Raft (multi-core only)

Skip in single-core mode and in multi-core deployments that opted out of mTLS (`storages.engines.rqlite.tls: null`).

For deployments configured by the bootstrap CLI, the cluster CA cert is at `/etc/pryv/tls/ca.crt` on every core, and rqlite's HTTP API speaks the same cert chain. Verify a peer's cert chains to the bundled CA:

```bash
# On core-a, against core-b's rqlite HTTP port (default 4001).
# Replace <core-b-host> with what core-b's node cert SAN advertises (its
# hostname or IP).
curl --cacert /etc/pryv/tls/ca.crt \
     --resolve <core-b-host>:4001:<core-b-ip> \
     https://<core-b-host>:4001/status
```

**Expected:** an HTTP 200 with rqlited's status JSON. A TLS handshake failure (`certificate verify failed`, `unknown CA`) means either the CA cert on this host is wrong, the peer is not actually using the cluster CA, or `verifyClient: true` is rejecting your client cert (in which case add `--cert /etc/pryv/tls/node.crt --key /etc/pryv/tls/node.key`).

If `dig`/`curl` lookups don't resolve `<core-b-host>` from this machine, use `--resolve` (as shown) to short-circuit DNS.


## Troubleshoot

### Core does not start

Inspect the logs:

```bash
docker logs -f --tail 200 pryvio_open_pryv_io
# or
journalctl -u pryv-core -f
```

Common causes:

- Malformed override YAML (`invalid config ...`). Run with `DEBUG=1` to get the full stack.
- Missing required `auth.adminAccessKey` / `auth.filesReadTokenSecret` / `service.*` keys — see [INSTALL — Minimal production config](https://github.com/pryv/open-pryv.io/blob/master/INSTALL.md#minimal-production-config).
- Port in use — usually another core or a stale process holding 3000/4000/4001/4002.
- `rqlited` binary missing — reinstall the image or re-run `just setup-dev-env`.

Export the tail of the log if you need to escalate:

```bash
docker logs --tail 200 pryvio_open_pryv_io > $(date -I)-pryv-core.log
```

### 502 / 504 from the reverse proxy

- Confirm the core is actually listening on 3000/4000: `ss -tlnp | grep -E '3000|4000'`.
- If the proxy is on a different host, check the firewall between them.
- For HFS specifically, ensure `proxy_set_header Host 127.0.0.1:4000;` is set — the HFS subdomain-to-path middleware breaks if a real domain is forwarded ([INSTALL note](https://github.com/pryv/open-pryv.io/blob/master/INSTALL.md#important-nginx-notes)).

### rqlite cluster split-brain or not converging

Only in multi-core mode. Symptoms: `/reg/*` returns 500, registrations fail, `/system/admin/cores` times out.

- Every core must run rqlited on the same Raft port (default 4002) and the port must be open between cores.
- The `lsc.${DOMAIN}` A record must list **every** core's IP — rqlited uses it for peer discovery.
- Inspect rqlite's local status: `curl http://localhost:4001/status` on each core. The `raft` block should agree on a single leader.
- Full troubleshooting: [rqlite.io documentation](https://rqlite.io/docs/).

### DNS does not resolve user subdomains

Only in multi-core mode with embedded DNS (`dns.active: true`).

- Check that the core process binds port 53 (`ss -ulnp | grep :53`). If Docker's embedded DNS or `systemd-resolved` is holding the port, free it or bind the core's DNS to a specific interface.
- Query the core directly, bypassing recursive resolvers: `dig @<core-ip> someuser.${DOMAIN}`.
- If the direct query works but public resolvers don't, the domain's NS records at the registrar are wrong.

### Base storage connection fails

- Credentials: re-read `storages.engines.postgresql.*` (or `mongodb.*`) in your override YAML.
- Network: from the core host, `nc -vz <db-host> 5432` (or `27017`).
- Permissions: PostgreSQL's `pg_hba.conf` must allow the core's IP; MongoDB's auth DB must contain the user.

### Permission denied on data directories

The core process must own (or at least be able to write to) `${DATA_DIR}/users`, `${DATA_DIR}/previews` and `${DATA_DIR}/rqlite-data`. Typical fix:

```bash
sudo chown -R <pryv-user>:<pryv-user> ${DATA_DIR}
```

For Docker: the default image runs as root, so permissions are usually only an issue when host-mounted volumes were pre-created by another user.
