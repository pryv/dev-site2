---
title: 'Subject Account Backup (DSAR / Portability)'
description: The subject-facing backup tools for GDPR right-of-access and portability requests, available as a CLI and a web app that export a portable account dump.
---


This guide describes the **subject-facing** backup tools — what an operator points a data subject at when they file a right-of-access (GDPR Art.15), portability (Art.20), or equivalent (CCPA §1798.110, PIPEDA Principle 4.9, Swiss nLPD Art.25, HIPAA-privacy §164.524) disclosure request. These are distinct from the operator-side disaster-recovery [`bin/backup.js`](/customer-resources/backup/) tool — that runs server-side with raw storage access for the operator's own backups, while the subject-facing tools run against the public API as the subject themself.

## Two flavors, one library

Both flavors use the same underlying library and produce a portable account dump suitable for handing to the subject:

- **CLI** — [`pryv-account-backup`](https://github.com/pryv/pryv-account-backup). Subjects (or implementers acting on a subject's behalf) clone the repo, `npm install`, run `npm start`. Useful for technical subjects, scripted batch exports, and the auditor-facing per-file sha256 integrity manifest.
- **Web app** — [`pryv-account-backup-webapp`](https://github.com/pryv/pryv-account-backup-webapp). Static site you deploy on your domain. Subjects log in via a web form, click **Start backup**, download a series of ZIP files. Minimum-friction for non-technical subjects; covers the read-side text resources.

Both flavors are git-clone-distributed — neither is on the npm registry. Pin to a tagged release via `github:pryv/<repo>#<tag>` in your fork's `package.json`.

## What's in a bundle

Per-user backup output (CLI writes to a folder; webapp writes to a series of ZIP files):

| Resource | CLI | Web app | Notes |
|---|:-:|:-:|---|
| Account info | ✅ | ✅ | `account.json` — username, language, system-streams account tree |
| Streams hierarchy | ✅ | ✅ | `streams.json` (`?state=all` if trashed data included) |
| Accesses (current) | ✅ | ✅ | `accesses.json` |
| Accesses (deletions + expired) | ✅ | ✅ | `accesses-all.json` — full disclosure-history view for Art.15(1)(c) |
| Profile (private + public) | ✅ | ✅ | `profile_private.json` / `profile_public.json` |
| Per-app profiles | ✅ | ✅ | `app_profiles/profile_app_<accessId>.json` per `app`-type access |
| Audit log | ✅ | ✅ | `audit_logs.json` — fetched via the standard events API on the `:_audit:*` store streams |
| Events (initial run) | ✅ | ✅ | `events-YYYY-MM.json` — one per UTC month in the discovered range |
| Events (incremental run) | ✅ | ✅ | `events-incremental-<TS>.json` — only events `modified > T` |
| Per-access version history (opt-in) | ✅ | ✅ | `accesses-history/<accessId>.json` per access |
| Attachments (opt-in) | ✅ | ✅ | `attachments/<eventId>_<fileName>` — binary streams piped chunk-by-chunk through the `StorageWriter` (CLI + webapp since v0.7.0) |
| High-frequency series data (opt-out) | ✅ | ✅ | `hf-data/<eventId>.json` per `series:*` event (CLI + webapp since v0.7.0) |
| Webhooks per access (opt-out) | ✅ | ✅ | `webhooks.json` aggregated by `accessId` (CLI + webapp since v0.7.0); expired (401/403) tokens skipped silently and non-fatally |
| Portable sync state | ✅ | ✅ | `sync-state.json` — kv-only snapshot (`lastRunAt` + per-resource `lastModifiedSince` + tool/format version). CLI auto-reads on the next run; webapp accepts it as an upload on the login screen for cross-browser / cross-device incremental |
| sha256 integrity manifest | ✅ | ❌ | `manifest.json` — tamper-evidence for third-party auditors; webapp omits by design (the ZIP is signed by the operator's TLS already) |

Both flavors now cover every read-side resource. The only artefact the webapp does not produce is the per-file sha256 integrity manifest — auditor-facing, available only on the CLI side. For subjects whose disclosure is going to a third-party auditor that wants tamper-evidence, route them at the CLI.

## Incremental backup

Both flavors persist a small state object after each successful run:

- CLI: `.sync-state.json` (hidden operational store) sentinel in the backup directory; auto-migrates from a pre-v0.7.0 `.state.json` on first read.
- Web app: `localStorage` keyed by the subject's apiEndpoint.

Both also write a **portable `sync-state.json`** (no leading dot) at run-end — CLI lands it next to the JSON resources; webapp embeds it inside the final ZIP. The subject keeps it alongside the backup; on the next run the file drives cross-session / cross-device incremental. The webapp's pre-login state panel offers an upload picker for the file (along with a per-saved-state Reset action), so a subject who switches browser / clears site data / runs from a different device still gets a true incremental backup.

On the next run, the tool fetches only events + audit rows with `modified > T` where `T` is the previous `runStartedAt`. Small resources (accesses, streams, profile) are full-re-fetched each run because their payloads are small; refs for attachments / HFS series / webhooks are populated by tee-parsing the events + accesses streams, drained by the per-method modules, and pruned at run-end (their work is per-run, not carried across runs).

## Audit log handling

Audit is a regular `@pryv/datastore` mounted at the `:_audit:*` store prefix on every Pryv core. The backup tools query audit via the standard events API:

```
GET /events?streams=[":_audit:accesses",":_audit:actions"]&modifiedSince=T&includeDeletions=true
```

The output filename `audit_logs.json` and content shape are stable across v0.4.0+ — third-party consumers that keyed on the file path continue to work.

The dedicated `/audit/logs` route was **removed** from open-pryv.io on 2026-06-15 (commit `19d1c11f`). Older backup-tool versions that call this route directly are now production-broken for the audit-log section of the bundle against any deployment running that build. **v0.6.0 is the minimum required subject-side backup tool version** — older versions silently produce empty `audit_logs.json` files (or hit 404s).

## Operator security note

The bundle carries `profile_private.json`, which includes the subject's MFA recovery codes (`profile.mfa.recoveryCodes` — 10 SMS-bypass tokens) when MFA is enabled. **Treat downloaded bundles as a secret on par with a password-reset link.** Transport over a secure channel; document destruction policy; consider asking the subject to rotate MFA recovery codes after the disclosure is complete.

This applies to BOTH the CLI and webapp output. The recovery codes ride verbatim because the subject is entitled to their full MFA state — but a leaked bundle becomes a MFA-bypass vector.

## MFA-enabled subjects

The webapp does **not** handle MFA challenges. If the subject has MFA enabled, point them at the CLI flavor — the CLI inherits MFA handling from lib-js's `Service.login` SMS-challenge flow.

## Deploy the web app

```bash
git clone https://github.com/pryv/pryv-account-backup-webapp.git
cd pryv-account-backup-webapp
npm install
npm run build              # produces dist/
```

Serve `dist/` from any static HTTP server **on the same origin as the Pryv API** (or with CORS configured for cross-origin access). For local development:

```bash
npm run serve              # esbuild dev server at http://127.0.0.1:8080
```

Production deployment is a static-file copy — no backend, no Express, no Docker.

## CLI walkthrough

```bash
git clone https://github.com/pryv/pryv-account-backup.git
cd pryv-account-backup
npm install
npm start
```

The CLI prompts for service-info URL, username, password, trashed-data inclusion, attachments inclusion, events chunk size, per-access version history inclusion. The output lands in `./backup/<apiEndpoint>/`, with a portable `sync-state.json` next to the JSON resources. Restore via `npm run restore <path-to-backup-directory>` (marked experimental — audit / webhooks / accesses are deliberately not replayed).

## Related

- Operator-side disaster-recovery backup: [`bin/backup.js`](/customer-resources/backup/).
- Library + CLI source: [`pryv-account-backup`](https://github.com/pryv/pryv-account-backup) + its `AGENTS.md`.
- Sample web app: [`pryv-account-backup-webapp`](https://github.com/pryv/pryv-account-backup-webapp) + its `AGENTS.md`.
- Previous-generation operator-hosted backup service (archived): [`pryv/example-service-bluebutton`](https://github.com/pryv/example-service-bluebutton). Superseded by the webapp.
