---
title: 'Pryv.io Backup'
---


This guide describes how the **operator** backs up a Pryv.io platform and restores from a backup — the disaster-recovery / migration story. For the **subject-facing** backup tools (what to point a data subject at when they file a DSAR / portability request), see [Subject Account Backup](/customer-resources/subject-account-backup/).

> **Since v2 (2026)** Pryv.io ships a built-in backup/restore tool, `bin/backup.js`. Prefer it over raw database dumps — it understands Pryv.io's data model, backs up per user, supports incremental runs, can verify integrity on restore, and can **encrypt its output on demand** so no plaintext personal/health data touches the backup media. For any backup that leaves the host (off-site, outsourced, or third-party storage) you should [encrypt it](#encrypting-the-backup). Raw database/filesystem dumps are still documented below as a disaster-recovery alternative for operators who need them (offline DB snapshots, block-level volume backups, etc.).


## Table of contents <!-- omit in toc -->

1. [Recommended: `bin/backup.js`](#recommended-binbackupjs)
   1. [Full backup](#full-backup)
   2. [Incremental backup](#incremental-backup)
   3. [Backup a single user](#backup-a-single-user)
   4. [Encrypting the backup](#encrypting-the-backup)
   5. [Restore](#restore)
   6. [What's in the backup](#whats-in-the-backup)
2. [Alternative: raw database + filesystem dumps](#alternative-raw-database--filesystem-dumps)
   1. [What to back up](#what-to-back-up)
   2. [Dump PostgreSQL](#dump-postgresql)
   3. [Restore raw dumps](#restore-raw-dumps)
3. [Important notice on consistency](#important-notice-on-consistency)


## Recommended: `bin/backup.js`

Run from the `open-pryv.io` repository root. The tool uses the same config files as the running core, so point `NODE_ENV` and `--config` at the same override you use in production.

### Full backup

```bash
NODE_ENV=production node bin/backup.js --output /backups/pryv-$(date +%Y%m%d)
```

The backup is a directory containing gzipped chunk files and a `manifest.json`. Default chunk size is 50 MB compressed — tune with `--max-chunk-size`.

For any backup that leaves the host, add encryption — the recommended form encrypts to a recipient public key so the backup host holds no decryption secret:

```bash
NODE_ENV=production node bin/backup.js --output /backups/pryv-$(date +%Y%m%d) --recipient-pubkey recipient.pub.pem
```

See [Encrypting the backup](#encrypting-the-backup) for the key setup and the passphrase alternative.

### Incremental backup

Point `--output` at an existing backup directory and add `--incremental`. The tool reads the previous `manifest.json` and exports only data that changed per user since the last backup:

```bash
node bin/backup.js --output /backups/pryv-rolling --incremental
```

If the directory does not yet contain a manifest, the tool falls back to a full backup.

### Backup a single user

```bash
node bin/backup.js --output /backups/alice --user <userId>
```

### Encrypting the backup

Backups can be **encrypted on demand** so that no plaintext personal/health data ever touches the destination disk — the bytes written to the backup media are ciphertext only. This is **opt-in**: without the flags below, the backup is plaintext as described above.

There are two key models. Encryption composes with everything else (`--incremental`, `--max-chunk-size`, `--user`, `--no-compress`).

**Recipient public key (recommended).** A fresh random data key encrypts the backup and is itself wrapped with a recipient **RSA public key**. The machine producing the backup never holds a secret that can decrypt its own output — only the holder of the matching private key can restore it. This is the strongest posture when the backup is shipped to outsourced or third-party storage.

```bash
# one-time: generate a recipient keypair, keep the private key offline/secure
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out recipient.key.pem
openssl pkey -in recipient.key.pem -pubout -out recipient.pub.pem

# backup, encrypting to the public key
node bin/backup.js --output /backups/pryv-$(date +%Y%m%d) --recipient-pubkey recipient.pub.pem
```

**Passphrase.** Simpler, but the same machine can decrypt its own backups. The data key is derived from a passphrase; pass it via `--encrypt-passphrase` or, to keep it out of the process list, the `PRYV_BACKUP_PASSPHRASE` environment variable.

```bash
PRYV_BACKUP_PASSPHRASE='…' node bin/backup.js --output /backups/pryv-$(date +%Y%m%d)
```

An encrypted backup carries a small cleartext `encryption.json` at its root (crypto headers + the wrapped key only — never user data) plus a self-contained `decrypt-backup.mjs` and `RESTORE-README.md`, so the key holder can decrypt it with only Node.js installed, even on a machine without Pryv.io.

> **Disaster recovery:** if the key (or passphrase) is lost, the backup is unrecoverable — that is the point. Manage the recipient private key / passphrase like any other root secret, and keep it separate from the backup media.

### Restore

Into an **empty** install (recommended):

```bash
node bin/backup.js --restore /backups/pryv-20260414
```

Into an install that already has conflicting users, pick one:

- `--overwrite` — clear the target user's data first and reimport.
- `--skip-conflicts` — leave conflicting users alone; only import the rest.

Restore auto-detects an encrypted backup (from its `encryption.json`) and asks for the matching secret:

- `--private-key recipient.key.pem` (plus `--private-key-passphrase` if the key file is itself passphrase-protected) for a backup made with `--recipient-pubkey`.
- `--decrypt-passphrase '…'` (or `PRYV_BACKUP_PASSPHRASE`) for a backup made with a passphrase.

Useful restore flags:

- `--verify-integrity` — after restore, verify event/access integrity hashes and roll back any user whose hashes don't match.
- `--user <userId>` — restore just one user.
- `--delete-on-success` / `--move-on-success <path>` — housekeep the backup directory after a successful restore.

### What's in the backup

`bin/backup.js` exports, per user:

- account info (system-stream events, emails, etc.)
- streams and events (including integrity hashes)
- accesses
- attachments (file blobs)
- high-frequency series
- audit records (if audit is active)

It does **not** export: sessions and password-reset tokens (add `--include-ephemeral` if you want them), rqlite platform-DB state (see below), user-level webhooks' ephemeral queue, or your YAML configuration files.


## Alternative: raw database + filesystem dumps

Use this path when you need full block-level or native-DB snapshots — for example when integrating with an existing backup solution, or when planning a bit-identical disaster-recovery restore.

### What to back up

1. **Base storage database** — PostgreSQL — holds events, streams, accesses. (If using the SQLite base-storage engine instead, its per-user files live under `data/users/`, covered by step 2.)
2. **Per-user filesystem data** — the `data/users/` tree holds SQLite DBs (audit, user index, per-user account) and attachment files. See [INSTALL — Data directories](https://github.com/pryv/open-pryv.io/blob/master/INSTALL.md#data-directories).
3. **Series engine data** — if using InfluxDB for HFS, back up InfluxDB. If using PostgreSQL for HFS, it is already covered by step 1.
4. **Previews** (`data/previews/`) — optional; previews can be regenerated from attachments.
5. **Platform DB** (`data/rqlite-data/`) — rqlite Raft log and snapshot. In single-core mode a snapshot is enough; in multi-core mode this is rebuilt from peer state when a core is reinstalled, so snapshotting is optional.
6. **Your override YAML(s)** — the override-config file(s) passed to `bin/master.js`.

Stop the core (or the specific user's activity) before dumping to avoid half-written events between step 1 and step 2.

### Dump PostgreSQL

```bash
pg_dump -U postgres -Fc pryv_db > /backups/pryv-$(date +%Y%m%d).dump
```

**InfluxDB** (only if used):

```bash
influxd backup -portable /backups/pryv-influx-$(date +%Y%m%d)
```

Back up `data/users/` alongside the DB dump with any filesystem tool (`rsync`, `tar`, volume snapshot, etc.).

### Restore raw dumps

Restore into an install of the **same core version** with an empty database and empty `data/users/`:

```bash
# PostgreSQL
createdb -U postgres pryv_db
pg_restore -U postgres -d pryv_db /backups/pryv-20260414.dump

# InfluxDB (if used)
influxd restore -portable /backups/pryv-influx-20260414
```

Then restore the `data/users/` tree in place, start the core, and check the [healthchecks](/customer-resources/healthchecks/).


## Important notice on consistency

Backups taken while the core is running can be **inconsistent** — events written between the DB dump and the filesystem snapshot may reference attachments that weren't yet copied (or vice versa), and new users registered mid-backup won't have all their data captured.

To guarantee consistency:

- Prefer `bin/backup.js`, which reads each user's data in a single pass.
- For raw dumps, stop the core before dumping, or use the host's snapshot feature (LVM, ZFS, cloud volume snapshot) to capture both the DB and the filesystem at the same instant.
- Document and test your restore procedure at least once per year — an untested backup is not a backup.
