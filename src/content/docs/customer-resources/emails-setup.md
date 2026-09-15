---
title: 'Open Pryv.io email configuration'
description: How to configure transactional emails in Open Pryv.io (welcome, password reset, email verification, registration code), comparing the in-process and legacy microservice delivery paths.
---


Open Pryv.io sends four kinds of transactional email:

| Type | Sent when | Template | Switch |
|---|---|---|---|
| **welcome** | after an account is created | `welcome-email` | `services.email.enabled.welcome` |
| **password reset** | after a reset request | `reset-password` | `services.email.enabled.resetPassword` |
| **email verification** | an address is added to an account, or a verification is requested again. Carries a one-time link. | `verify-email` | `services.email.enabled.verifyEmail` (**on by default**) |
| **registration code** | the sign-up gate is on and a client requests a code for an address. Carries a copy/paste code, not a link. | `email-challenge` | `account.emailVerification.requireAtRegistration` |

All four share the same SMTP transport and Pug template pipeline. The last two are described in [Email verification](#email-verification).

v2 supports two delivery paths. Pick one at `services.email.method` in `override-config.yml`:

| `method` | Runs | Templates live in | Use when |
|---|---|---|---|
| `in-process` (recommended) | The api-server worker that handled registration / reset-password | PlatformDB (rqlite, cluster-wide) | Single- and multi-core v2 deployments. No extra process, one less localhost hop, templates editable via CLI + admin API. |
| `microservice` (legacy) | A separate `service-mail` process on each core bound to `127.0.0.1:9000` | Disk files under `templates/` on the `service-mail` box | Existing deployments still running the standalone `pryv/service-mail` process. |

Everything below assumes v2 (`open-pryv.io`). v1 deployments configured the same two delivery paths under `services.email.method: mandrill | microservice` in `core/core/conf/core.json`, with templates in a separate `pryv/mail` Docker container or via Mandrill's hosted templates — that surface is no longer used in v2.

## Choose a method <a name="choose-a-method"></a>

Set `services.email.method` in `override-config.yml`. The default is `in-process` since the merged mail component landed in v2; deployments that still run the external `pryv/service-mail` process must pin `method: microservice` themselves.

```yaml
services:
  email:
    method: in-process            # or 'microservice'
    enabled:
      welcome: true
      resetPassword: true
      verifyEmail: true           # on by default, see 'Email verification' below
```


## Common config — SMTP, sender, language <a name="common-config"></a>

These apply to both methods. SMTP credentials and the sender identity are always per-core, local to `override-config.yml` — they do not propagate through PlatformDB.

```yaml
services:
  email:
    defaultLang: en                # applied when the request has no `language` field
    welcomeTemplate: welcome-email
    resetPasswordTemplate: reset-password
    verifyEmailTemplate: verify-email
    emailChallengeTemplate: email-challenge
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


## Email verification

Two independent features prove that an email address belongs to the person holding it.

- **On an account** (`services.email.enabled.verifyEmail`, **on by default**): every address on an account carries a status. Adding an address mails a one-time link to it; following the link marks that address verified. This is what the `verify-email` template renders.
- **At registration** (`account.emailVerification.requireAtRegistration`, off by default): creating an account requires proving the address first, with a code the holder copies out of the mail. This is what the `email-challenge` template renders.

Neither replaces the other. You can require a proved address at sign-up, let account holders verify further addresses afterwards, or both.

### On an account: the link flow

Besides the switch, the feature needs two things:

1. `auth.emailVerificationPageURL`, the `/verify-email` page of your auth UI. The mailed link points there and carries `verifyToken` and `username` as query parameters (the separator is chosen at build time, so a page URL that already has its own query keeps working). That page then calls `POST /:username/account/verify-email` with the token.
2. A working `services.email` setup, in the sense of [the table below](#what-a-working-mail-setup-means).

**Soft landing on upgrade.** If either is missing and you never set `services.email.enabled.verifyEmail` yourself, the core still boots, logs **one warning per boot**, and the feature stays off: no verification mail is sent and account addresses cannot be proved. Setting `verifyEmail: true` **explicitly** makes `auth.emailVerificationPageURL` required, so the boot fails fast instead of warning. Setting it to `false` turns the feature off silently and stops the warning.

The warning reads:

```
email verification is on by default but 'auth.emailVerificationPageURL' is not set:
verification mails are not sent and account email addresses cannot be proved.
Set the missing keys (the page is the /verify-email route of your auth UI), or set
'services.email.enabled.verifyEmail: false' to turn the feature off explicitly.
```

Run `node bin/check-config.js <your-config.yml>` to get the same verdict offline, before restarting anything.

### What "a working mail setup" means

One config-only predicate backs the boot check, `bin/check-config.js`, the runtime gate and `/service/info`, so those four can never disagree about whether a verification mail would be sent. It answers "is mail configured", never "is the mail server reachable": no SMTP probe runs at boot, so a transient relay outage cannot turn a restart into a failed one.

| `services.email.method` | Required for the platform to count as mail-capable |
|---|---|
| `in-process` | `services.email.smtp.host` |
| `microservice` | `services.email.url` and `services.email.key` |
| `mandrill` | `services.email.url` and `services.email.key` |

`services.email.from.name` and `.address` are deliberately **not** required: the transport omits the header when they are unset, so a deployment that has been sending mail without a configured sender keeps working. Set them anyway, since some relays reject sender-less messages.

### At registration: the code flow

Set `account.emailVerification.requireAtRegistration: true` to require a proved address before an account can be created. The client then:

1. posts the address to `POST {serviceInfo.register}email-challenge`. The core mails an 8-character code, displayed as `XXXX-XXXX`, to that address;
2. sends the code the holder pasted back to `POST {serviceInfo.register}email-challenge/verify`, which answers with an `emailProof`;
3. passes that proof to `POST {serviceInfo.register}users`. Registration without it is refused.

The founding address of an account created this way is recorded as proved, with `verificationMethod: email-code`.

What to know before turning it on:

- **The core refuses to boot** when the gate is on and `services.email` is incomplete. The gate cannot work without mail, and failing at boot beats refusing every registration at runtime.
- **A delivery failure blocks the registration** (fail closed) rather than letting an unverified account through.
- **Set the same value on every core of a cluster.** Codes and proofs live in PlatformDB and are cluster-wide, so a code minted on one core verifies on any other; the gate flag itself is read per core.
- **With `microservice` or `mandrill` delivery, the `email-challenge` template lives on that external service**, not in PlatformDB. Add it there before turning the gate on, or the first registration fails closed on a send error.
- **Admin-created accounts (`system.createUser`) are never gated.**
- **The rate limits are keyed on the target address**, because these endpoints are public and have no caller identity to key on. Someone who knows an address that has no account yet can therefore spend its daily budget and lock it out of sign-up until the window rolls, mailing it a code each time. The caps are deliberately soft, sized to stop bulk abuse rather than a targeted nuisance. Put a per-IP rate limit in front of the registration endpoints at the edge if that matters to you.

### Verification config keys

| Key | Default | Meaning |
|---|---|---|
| `services.email.enabled.verifyEmail` | `true` | The account verification mail. |
| `auth.emailVerificationPageURL` | unset | The `/verify-email` page the mailed link points at. |
| `services.email.verifyEmailTemplate` | `verify-email` | Template for the link mail. |
| `services.email.emailChallengeTemplate` | `email-challenge` | Template for the registration code mail. |
| `account.maxEmails` | `5` | Addresses per account, primary included. Clamped to a hard ceiling of 20. |
| `account.emailVerification.tokenMaxAgeMs` | `86400000` (24h) | How long a verification link stays valid. |
| `account.emailVerification.resendCooldownMs` | `300000` (5min) | Minimum delay between two verification mails for the same address. |
| `account.emailVerification.requireAtRegistration` | `false` | The sign-up gate. |
| `account.emailVerification.registrationCodeMaxAgeMs` | `600000` (10min) | Lifetime of a registration code. |
| `account.emailVerification.registrationCodeMaxAttempts` | `5` | Wrong tries before a code is discarded. |
| `account.emailVerification.registrationCodeResendCooldownMs` | `60000` (1min) | Minimum delay between two codes for the same address. |
| `account.emailVerification.registrationCodeDailyLimit` | `10` | Codes per address per day. |
| `account.emailVerification.registrationCodeFailuresPerDay` | `20` | Wrong tries per address per day, across codes. |
| `account.emailVerification.registrationProofMaxAgeMs` | `1800000` (30min) | How long a successful proof stays usable for registering. |

### What clients see

`GET /service/info` always advertises both switches, so an app can adapt its sign-up and account screens without guessing:

```json
{
  "features": {
    "emailVerification": { "atRegistration": false, "onAccount": true }
  }
}
```

`onAccount` is true only when a verification mail would actually be sent: switch on, page URL set, mail configured. `atRegistration` mirrors `account.emailVerification.requireAtRegistration` exactly, because the boot check has already refused an incapable configuration.


## `in-process` mode (recommended) <a name="in-process-mode"></a>

In-process mode renders Pug templates inside the api-server workers that already handle registration and password-reset. Templates live in the cluster-wide PlatformDB (rqlite) and propagate automatically to every core.

### Boot-time template seeding <a name="boot-time-template-seeding"></a>

On the **first** boot with an empty PlatformDB, the master seeds the **template set bundled with the mail component** (`welcome-email`, `reset-password`, `verify-email` and `email-challenge`, each in `en` and `fr`). A fresh install can therefore send all four mail classes without anyone authoring a template first.

To seed your own set instead, point `templatesRootDir` at an on-disk Pug directory. When the key is set, the bundled set is not used:

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
├── reset-password/
│   └── en/
│       ├── subject.pug
│       └── html.pug
├── verify-email/
│   └── ...
└── email-challenge/
    └── ...
```

Seeding is **idempotent**: if PlatformDB already has any `mail-template/*` row the master skips the seed and logs the count. Re-seeding after the first boot is the job of the CLI / admin API below — changing the files on disk does NOT re-seed, and neither does changing `templatesRootDir` later.

You can also populate PlatformDB from scratch at any time using the CLI `templates seed --from <dir>` or the `PUT /system/admin/mail/templates/:type/:lang/:part` admin route. Both overwrite existing rows.

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

Pug templates receive a `locals` object at render time. Names are upper-case. Use `#{VAR}` in Pug to interpolate a value, and `a(href=VAR)` to use one as an attribute.

### `welcome-email`

| Local | Example |
|---|---|
| `USERNAME` | `alice` |
| `EMAIL` | `alice@example.com` |

### `reset-password`

| Local | Example |
|---|---|
| `RESET_TOKEN` | opaque one-time token |
| `RESET_URL` | `https://sw.example.com/access/reset-password.html`, from `auth.passwordResetPageURL` |
| `RESET_LINK` | `RESET_URL` with the token appended |

### `verify-email`

| Local | Example |
|---|---|
| `USERNAME` | `alice` |
| `EMAIL` | the address being verified |
| `VERIFY_TOKEN` | opaque one-time token, printed in the mail so it can be pasted when the link does not open |
| `VERIFY_URL` | `auth.emailVerificationPageURL`, unchanged |
| `VERIFY_LINK` | `VERIFY_URL` plus `verifyToken` and `username` |

### `email-challenge`

| Local | Example |
|---|---|
| `EMAIL` | the address being proved |
| `CODE` | the code, already formatted as `XXXX-XXXX` |
| `CODE_MAX_AGE_MINUTES` | `10` |

Keep the code out of the subject line of a custom `email-challenge` template: subjects show up in lock-screen previews and in mail-server logs, and this code stamps an address as proved. The bundled subject says only that a code is inside.


## SPF record reminder <a name="spf-record-reminder"></a>

Whichever method you pick, SMTP servers use SPF to verify the sender. If you're emitting mail on behalf of your Pryv.io domain, add a TXT record to your DNS zone authorising your SMTP host:

```
@ 10800 IN TXT "v=spf1 include:spf.your-smtp-host.example ~all"
```

See [DNS configuration](/customer-resources/dns-config/) for where to put it in your zone.
