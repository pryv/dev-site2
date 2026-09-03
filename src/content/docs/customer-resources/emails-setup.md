---
title: 'Open Pryv.io email configuration'
---


Open Pryv.io sends two kinds of transactional email: the **welcome** message after account creation and the **password-reset** message after a reset request. Both are optional (disabled independently via `services.email.enabled.*`) and both share the same SMTP transport + Pug template pipeline.

v2 supports two delivery paths. Pick one at `services.email.method` in `override-config.yml`:

| `method` | Runs | Templates live in | Use when |
|---|---|---|---|
| `in-process` (recommended) | The api-server worker that handled registration / reset-password | PlatformDB (rqlite, cluster-wide) | Single- and multi-core v2 deployments. No extra process, one less localhost hop, templates editable via CLI + admin API. |
| `microservice` (legacy) | A separate `service-mail` process on each core bound to `127.0.0.1:9000` | Disk files under `templates/` on the `service-mail` box | Existing deployments still running the standalone `pryv/service-mail` process. |

Everything below assumes v2 (`open-pryv.io`). v1 deployments configured the same two delivery paths under `services.email.method: mandrill | microservice` in `core/core/conf/core.json`, with templates in a separate `pryv/mail` Docker container or via Mandrill's hosted templates — that surface is no longer used in v2.


## Table of contents <!-- omit in toc -->

1. [Choose a method](#choose-a-method)
2. [Common config — SMTP, sender, language](#common-config)
3. [`in-process` mode (recommended)](#in-process-mode)
    1. [Boot-time template seeding](#boot-time-template-seeding)
    2. [Managing templates — `bin/mail.js` CLI](#mail-cli)
    3. [Managing templates — admin HTTP API](#admin-http-api)
    4. [PlatformDB keyspace](#platformdb-keyspace)
    5. [Cluster propagation](#cluster-propagation)
4. [`microservice` mode (legacy)](#microservice-mode)
5. [Template variables](#template-variables)
6. [SPF record reminder](#spf-record-reminder)


## Choose a method <a name="choose-a-method"></a>

Set `services.email.method` in `override-config.yml`. Default is `microservice` for now; a future release will flip the default to `in-process` once both modes have had equal prod exposure.

```yaml
services:
  email:
    method: in-process            # or 'microservice'
    enabled:
      welcome: true
      resetPassword: true
```


## Common config — SMTP, sender, language <a name="common-config"></a>

These apply to both methods. SMTP credentials and the sender identity are always per-core, local to `override-config.yml` — they do not propagate through PlatformDB.

```yaml
services:
  email:
    defaultLang: en                # applied when the request has no `language` field
    welcomeTemplate: welcome-email
    resetPasswordTemplate: reset-password
    from:
      name: 'Pryv Lab no-reply'
      address: 'no-reply@your-domain.example'
    smtp:
      host: your-smtp-server
      port: 587
      secure: false
      auth:
        user: REPLACE_ME
        pass: REPLACE_ME
```

Need to use `sendmail` instead of SMTP for dev? Pass `smtp: { sendmail: true, path: '/usr/sbin/sendmail' }` — `nodemailer` honours the same field names as the previous service-mail layer.


## `in-process` mode (recommended) <a name="in-process-mode"></a>

In-process mode renders Pug templates inside the api-server workers that already handle registration and password-reset. Templates live in the cluster-wide PlatformDB (rqlite) and propagate automatically to every core.

### Boot-time template seeding <a name="boot-time-template-seeding"></a>

On the **first** boot with an empty PlatformDB, the master will seed templates from an on-disk Pug directory if you point it at one:

```yaml
services:
  email:
    method: in-process
    templatesRootDir: /opt/open-pryv.io/mail-templates
```

Directory layout expected:

```
/opt/open-pryv.io/mail-templates/
├── welcome-email/
│   ├── en/
│   │   ├── subject.pug
│   │   └── html.pug
│   └── fr/
│       ├── subject.pug
│       └── html.pug
└── reset-password/
    └── en/
        ├── subject.pug
        └── html.pug
```

Seeding is **idempotent**: if PlatformDB already has any `mail-template/*` row the master skips the seed and logs the count. Re-seeding after the first boot is the job of the CLI / admin API below — changing the files on disk does NOT re-seed.

If `templatesRootDir` is empty, no templates are seeded. You can instead populate PlatformDB from scratch using the CLI `templates seed --from <dir>` or the `PUT /system/admin/mail/templates/:type/:lang/:part` admin route — both overwrite existing rows.

### Managing templates — `bin/mail.js` CLI <a name="mail-cli"></a>

Run from inside the `open-pryv.io` directory on any core:

```sh
node bin/mail.js templates list
# → type          lang  part     len
#   welcome-email en    html     482
#   welcome-email en    subject   18
#   ...

node bin/mail.js templates get welcome-email en html
# → prints the current Pug source to stdout

node bin/mail.js templates set welcome-email en html --file ./new-welcome.pug
# → overwrites the html part. CLI doesn't push IPC; sibling workers refresh
#   on their next request via the admin API path or the periodic cache re-read.

node bin/mail.js templates delete welcome-email fr        # wipes both parts for fr
node bin/mail.js templates delete welcome-email fr subject   # wipes only subject

node bin/mail.js templates seed --from /opt/open-pryv.io/mail-templates
# → OVERWRITES every row that exists on disk. Use this to bulk-replace.

node bin/mail.js send-test welcome-email en alice@example.com
# → renders the template with stub substitutions and sends a real email
#   through the configured SMTP transport.
```

### Managing templates — admin HTTP API <a name="admin-http-api"></a>

All routes live under `/system/admin/mail/` on every core and require the platform admin key (`auth.adminAccessKey`) as the `Authorization` header. Unauthorized requests return 404 (by design, to avoid advertising the surface).

| Method | Path | Body | Response |
|---|---|---|---|
| `GET`    | `/system/admin/mail/templates`                        | —                          | `{ templates: [{type,lang,part,length}] }` |
| `GET`    | `/system/admin/mail/templates/:type/:lang/:part`      | —                          | `text/plain` raw Pug |
| `PUT`    | `/system/admin/mail/templates/:type/:lang/:part`      | `{ "pug": "<source>" }`    | 204 |
| `DELETE` | `/system/admin/mail/templates/:type/:lang/:part`      | —                          | 204 |
| `POST`   | `/system/admin/mail/send-test`                        | `{ type, lang, recipient }` | `{ sent: true }` |

`PUT` and `DELETE` both trigger a cross-worker refresh on the local core via IPC so the new content is live on the next request without a restart.

Example:

```sh
ADMIN_KEY=...
curl -sS -X PUT https://core-use1.example/system/admin/mail/templates/welcome-email/en/subject \
  -H "Authorization: $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  --data-binary '{ "pug": "| Welcome to Example" }'
```

### PlatformDB keyspace <a name="platformdb-keyspace"></a>

Templates are stored as raw Pug strings under:

```
mail-template/<type>/<lang>/<part>
```

`<part>` is `subject` or `html`. The value is compiled on demand at render time; the compiled function is cached in the worker's memory alongside the raw source. A refresh nudge (IPC broadcast or process restart) drops the compiled cache too.

### Cluster propagation <a name="cluster-propagation"></a>

- **Same core, multiple workers** — after a `PUT` or `DELETE`, the worker that handled the write sends `mail:template-invalidate` over IPC. Master broadcasts it to every sibling worker; each sibling re-materialises its local tmp-dir of Pug sources on receipt.
- **Across cores** — rqlite replicates the `mail-template/*` row to every other core. The next request on those cores reads the new value directly from PlatformDB on a refresh. No cross-core IPC needed.
- **New core joining the cluster** — a freshly bootstrapped core sees the existing templates via rqlite replication as soon as it joins the Raft group. No re-seed needed.


## `microservice` mode (legacy) <a name="microservice-mode"></a>

If you are still running the standalone `pryv/service-mail` process alongside each core, set:

```yaml
services:
  email:
    method: microservice
    url: http://127.0.0.1:9000/sendmail/
    key: your-shared-auth-key        # matches http.auth on the service-mail side
```

- Templates live on disk under `service-mail/templates/<type>/<lang>/{subject,html}.pug`. Edit, restart, repeat — no hot reload.
- `services.email.smtp.*` and `services.email.from.*` in open-pryv.io are ignored in this mode; SMTP creds live on the service-mail side.
- The `pryv/service-mail` GitHub repo is supported for the v2 2.0.0 line. It will be archived once `in-process` becomes the default.


## Template variables <a name="template-variables"></a>

Pug templates receive a `locals` object at render time. The two shipped types expect:

### `welcome-email`

| Local | Example |
|---|---|
| `username` | `alice` |
| `email` | `alice@example.com` |

### `reset-password`

| Local | Example |
|---|---|
| `username` | `alice` |
| `email` | `alice@example.com` |
| `resetUrl` | `https://sw.example.com/access/reset-password.html` |
| `resetToken` | 32-char opaque token |

Use `#{var}` in Pug to interpolate.


## SPF record reminder <a name="spf-record-reminder"></a>

Whichever method you pick, SMTP servers use SPF to verify the sender. If you're emitting mail on behalf of your Pryv.io domain, add a TXT record to your DNS zone authorising your SMTP host:

```
@ 10800 IN TXT "v=spf1 include:spf.your-smtp-host.example ~all"
```

See [DNS configuration](/customer-resources/dns-config/) for where to put it in your zone.
