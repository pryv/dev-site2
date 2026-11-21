---
title: 'Pryv.io Backup'
description: How an operator backs up and restores a Pryv.io platform with the built-in bin/backup.js tool, including encrypted, incremental and raw-dump options.
---


This guide describes how the **operator** backs up a Pryv.io platform and restores from a backup — the disaster-recovery / migration story. For the **subject-facing** backup tools (what to point a data subject at when they file a DSAR / portability request), see [Subject Account Backup](/customer-resources/subject-account-backup/).

> **Since v2 (2026)** Pryv.io ships a built-in backup/restore tool, `bin/backup.js`. Prefer it over raw database dumps — it understands Pryv.io's data model, backs up per user, supports incremental runs, can verify integrity on restore, and can **encrypt its output on demand** so no plaintext personal/health data touches the backup media. For any backup that leaves the host (off-site, outsourced, or third-party storage) you should [encrypt it](#encrypting-the-backup). Raw database/filesystem dumps are still documented below as a disaster-recovery alternative for operators who need them (offline DB snapshots, block-level volume backups, etc.).

## Recommended: `bin/backup.js`

Run from the `open-pryv.io` repository root. The tool uses the same config files as the running core, so point `NODE_ENV` and `--config` at the same override you use in production.

### Full backup

```bash
NODE_ENV=production node bin/backup.js --output /backups/pryv-$(date +%Y%m%d)
```

The backup is a directory containing gzipped chunk files and a `manifest.json`. Default chunk size is 50 MB compressed — tune with `--max-chunk-size`.

A backup directory holds the backup only. Since 2.0.0-rc.86 a backup refuses to start in a directory that already holds other files (the leftovers of an interrupted full backup: remove them or use a new directory), and refuses to complete a run when a file appeared in its directory while it was written.

For any backup that leaves the host, add encryption — the recommended form encrypts to a recipient public key so the backup host holds no decryption secret:

```bash
NODE_ENV=production node bin/backup.js --output /backups/pryv-$(date +%Y%m%d) --recipient-pubkey recipient.pub.pem
```

See [Encrypting the backup](#encrypting-the-backup) for the key setup and the passphrase alternative.

### Incremental backup

Point `--output` at an existing backup directory and add `--incremental`. The tool exports, per user, only what changed since the previous run, and writes it **next to** the earlier runs, never over them:

```bash
node bin/backup.js --output /backups/pryv-rolling --incremental
```

If the directory does not yet contain a backup, the tool takes a full backup instead.

A backup directory is a **chain**: the full backup at its root, then one `incrementals/<runId>/` directory per incremental run, each with its own `manifest.json` (and its own `encryption.json` when encrypted). The cleartext `chain.json` at the root lists the runs in order. No run ever rewrites a file of an earlier run.

- **Window.** An incremental run exports what changed since the previous run *started* (with a one-minute overlap that restore merges away), so nothing changed during the previous run is missed. Deletions count as changes: a deleted stream, access, webhook or event is carried as a deletion record.
- **Consistency.** A run is consistent as of its start; changes and deletions made while a run is in progress are captured by the next run.
- **Deleted accounts.** A run of the whole core (no `--user`) lists every account that exists. An account that a later whole-core run no longer lists was deleted, and is not restored (see [Restore](#restore)).
- **Same key model.** Continue an encrypted chain with the same passphrase or the same recipient public key (the private key is not needed on the backup host). The passphrase is checked against the previous run before anything is written; a different key model is refused: start a new chain in a new directory.
- **Inspect.** `node bin/backup.js --inspect <dir>` lists the runs (id, type, scope, snapshot time, user count, encryption, deleted accounts) and prints one verdict: `OK`, `DAMAGED`, `INCOMPLETE` or `UNKNOWN`. It reads the directory only.

> **Before 2.0.0-rc.51, `--incremental` overwrote the full backup.** It wrote the delta into the same files as the full backup and its restore reported success with the earlier data gone. A directory that ever received `--incremental` from an earlier version is damaged and cannot be repaired: it has no `chain.json` and its `manifest.json` says `"backupType": "incremental"` (`--inspect` prints `DAMAGED`; for an encrypted directory pass the same secret as for a restore). Restore refuses it (`--allow-incomplete` restores the delta anyway). Take a new full backup into a new directory and continue from there. Full backups written by earlier versions are not affected: they restore unchanged and can start a chain.

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

**Signing (recommended with a recipient public key, since 2.0.0-rc.86).** With a recipient public key alone, whoever holds that public key and can write to the backup destination could replace a run. Sign each run with an Ed25519 key so the restore can tell:

```bash
# one-time: generate a signing keypair
openssl genpkey -algorithm ed25519 -out backup-signing.key.pem
openssl pkey -in backup-signing.key.pem -pubout -out backup-signing.pub.pem

# backup, encrypted and signed
node bin/backup.js --output /backups/pryv-rolling --incremental --recipient-pubkey recipient.pub.pem --signing-key backup-signing.key.pem
```

Keep the private signing key on the backup host and the public key with the restore secret, and pass it at restore (`--signing-pubkey`): every run must then be signed by that key, or the restore is refused. The backup prints a warning when a run is not signed, and a restore of a signed backup without `--signing-pubkey` warns that the signatures are not verified. Signing starts with a full backup: a chain that was started unsigned cannot be signed later; take a new full backup into a new directory.

**Passphrase.** Simpler, but the same machine can decrypt its own backups. The data key is derived from a passphrase; pass it with `--passphrase-file <path>` (first line of the file), or the `PRYV_BACKUP_PASSPHRASE` environment variable. `--encrypt-passphrase` also works but shows the passphrase in the process list and the shell history.

```bash
node bin/backup.js --output /backups/pryv-$(date +%Y%m%d) --passphrase-file /etc/pryv/backup-passphrase
```

Since 2.0.0-rc.86, new passphrase-encrypted backups use a stronger key derivation: about 134 MiB of memory once per run. Existing backups are unaffected.

An encrypted backup carries a small cleartext `encryption.json` at its root (crypto headers and the wrapped key only, never user data) plus a self-contained `decrypt-backup.mjs` and `RESTORE-README.md`, so the key holder can decrypt it with only Node.js installed, even on a machine without Pryv.io. Every run of a chain carries its own `encryption.json` and, since 2.0.0-rc.51, its own copy of the script and README: **use the newest run's script**: run from the backup directory, `node incrementals/<runId>/decrypt-backup.mjs` decrypts the whole chain (given a run directory, the script climbs to the chain's root). A full backup taken before 2.0.0-rc.51 keeps an older script at its root that does not know incremental runs.

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
- `--passphrase-file <path>` (or `PRYV_BACKUP_PASSPHRASE`, or `--decrypt-passphrase`) for a backup made with a passphrase.
- `--signing-pubkey backup-signing.pub.pem` for a signed backup (see [Signing](#encrypting-the-backup)).

Since 2.0.0-rc.86 every file of a run is listed in the run's manifest with its size and hash: a run whose files were added, removed, changed or cut short is refused, and an account's files are checked before anything of the account is written. A file the backup did not write, found in a run's directory, is also refused; files that operating systems and storage appliances create by themselves (`.DS_Store`, `._*`, `Thumbs.db`, `desktop.ini`, `.nfs*`, `lost+found`, `@eaDir`, `.snapshot`, `.zfs`, ...) are ignored with a notice. `node bin/backup.js --inspect --verify-files <dir>` (with the backup's secret) reads and checks every file without restoring: run it after a backup, or before relying on one. A backup written before 2.0.0-rc.86 is restored without that check (its runs are reported as "file list not verified").

> **Upgrading and going back.** A backup written by 2.0.0-rc.86 or later is restored with that release or later. After going back to an earlier release, start a new chain in a new directory: a run that an earlier release appends to a chain of 2.0.0-rc.86 or later is refused at restore (`--through-run` stops before it).

Restoring a chain applies the full backup, then every incremental run in order: the newest version of a stream, access, event or attachment replaces the older one, deletions included. Accounts deleted along the chain are not restored; the restore report names them.

- `--through-run <runId>` restores the chain up to that run (the state as of that run; `--inspect` lists the run ids). It is also the way to restore an account as of the last run that held it.
- A run missing from the chain refuses the restore, naming the run and the `--through-run` that stops before it.

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
- the account's aliases (those of its `randomAlias` accesses and its former usernames), reserved again on restore; high-frequency series still kept under a former username are exported too and restored under the username (see [aliases and username changes](/customer-resources/aliases-and-username-changes/#backup-and-restore))

Each run's `manifest.json` lists every file of the run with its size and hash; a signed run also has a `manifest.sig`.

It does **not** export: sessions and password-reset tokens (add `--include-ephemeral` if you want them), rqlite platform-DB state (see below), user-level webhooks' ephemeral queue, or your YAML configuration files.

## Erased accounts on disk and in the database

From the release after 2.0.0-rc.87, work still running for an account while it is erased (a long request, a cross-account dispatch) can no longer store data for it. Two guards do this; both matter when you back up, restore or clean up a core.

### SQLite: the `erased.json` marker

With the SQLite storage and `audit.onUserDelete: keep`, an erasure leaves the account's directory under `data/users/` with its `audit-*` files and one marker file, `erased.json` (content `{"v":1,"erasedAt":<ms>}`, no username), and nothing else. While the marker is there, no new file is created in that directory: late work for the erased account is refused instead of opening new, empty databases next to the kept audit. The marker is on disk, so every process of the core reads it, and it survives restarts.

- **Do not delete `erased.json` to "clean up" a kept directory.** It is what keeps the directory to its audit files; removing it lets late work create empty databases there again.
- **A restore clears it.** `bin/backup.js --restore` (whole core or `--user`, with or without `--overwrite`) removes the marker of each account it brings back before writing its data; you do nothing by hand.
- Directories kept by erasures before this release carry no marker: empty databases found next to their audit files hold no row and may be removed.

### PostgreSQL: no row for an id the users index does not hold

The database refuses a new row for a user id that the users index does not hold (SQLSTATE `PU001`) in `events`, `streams`, `accesses`, `profile`, `webhooks`, `account_fields`, `passwords` and `store_key_values`. The erasure removes an account's index entry before its data, and an insert in flight holds that entry until it commits, so once the entry is gone no new row is stored for the account in those tables. The guard is installed at boot (function `refuse_unindexed_user()`, one `BEFORE INSERT` trigger per table; a trigger found disabled is enabled again with a warning) and by a migration. Rows already stored are not checked. A request refused this way answers `404` `unknown-resource` ("Unknown user"), and the server logs the refusal at warn with the table: outside an erasure, it points at a write under a wrong user id.

- **`bin/backup.js`** writes an account's index entry before its data and is not affected.
- **A full `pg_restore`** (schema and data) creates the triggers after the data and is not affected.
- **A data-only `pg_restore`** into an existing schema loads tables in an order that puts rows before their `users_index` entries: run it with `--disable-triggers`, or set `pryv.unindexed_writes = 'allow'` in that session (see [Restore raw dumps](#restore-raw-dumps)).

**Upgrading.** All processes of a core must run this release: a process of an earlier release writes a registration's personal access before the account's index entry, which the database now refuses (registration with a session fails). During the upgrade, do not let a process of the earlier release serve registrations once a process of this release has started on the database.

**Rolling back.** The earlier release does not remove the guard. Before going back to it, with every process stopped, remove it:

```sql
DROP TRIGGER IF EXISTS refuse_unindexed_user ON events;
DROP TRIGGER IF EXISTS refuse_unindexed_user ON streams;
DROP TRIGGER IF EXISTS refuse_unindexed_user ON accesses;
DROP TRIGGER IF EXISTS refuse_unindexed_user ON profile;
DROP TRIGGER IF EXISTS refuse_unindexed_user ON webhooks;
DROP TRIGGER IF EXISTS refuse_unindexed_user ON account_fields;
DROP TRIGGER IF EXISTS refuse_unindexed_user ON passwords;
DROP TRIGGER IF EXISTS refuse_unindexed_user ON store_key_values;
DROP FUNCTION IF EXISTS refuse_unindexed_user();
```

Starting this release again installs it again.


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

A full `pg_restore` as above is not affected by the [PostgreSQL guard on erased accounts](#postgresql-no-row-for-an-id-the-users-index-does-not-hold). A data-only restore (`--data-only`) into a schema that already exists is: add `--disable-triggers`, or run it in a session that has `SET pryv.unindexed_writes = 'allow'`. The `erased.json` markers in a restored `data/users/` tree are kept as they were dumped: leave them in place.


## Important notice on consistency

Backups taken while the core is running can be **inconsistent** — events written between the DB dump and the filesystem snapshot may reference attachments that weren't yet copied (or vice versa), and new users registered mid-backup won't have all their data captured.

To guarantee consistency:

- Prefer `bin/backup.js`, which reads each user's data in a single pass.
- For raw dumps, stop the core before dumping, or use the host's snapshot feature (LVM, ZFS, cloud volume snapshot) to capture both the DB and the filesystem at the same instant.
- Document and test your restore procedure at least once per year — an untested backup is not a backup.
