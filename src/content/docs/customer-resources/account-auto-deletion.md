---
title: 'Account auto-deletion'
description: How a Pryv.io platform deletes accounts at a date their holder chose or after a period without use, with reminder mails, a minimum notice and an optional operator preset. Settings, safeguards, mail templates and what the holder sees.
---

An account can be deleted automatically, at a date its holder chose, or after a period without use. The period is either the holder's choice or a preset of the platform. Reminder mails go out before the deletion, and no account is deleted without notice.

**Default: nothing is deleted.** A platform has no preset out of the box, so an account is only ever scheduled for deletion because its holder asked for it, and only where the platform allows its holders to delete their own account (see [Self-deletion](#self-deletion-user-accountdelete)).

Holders set their schedule with [`account.setAutoDeletion`](/reference/#methods-account-account-setAutoDeletion) and read it with [`account.getAutoDeletion`](/reference/#methods-account-account-getAutoDeletion), typically from the account app (`service.account`). Clients detect the feature through `features.autoDeletion` in [service info](/reference/#service-info).

## How it works

### Triggers

A schedule has exactly one trigger:

- **`date`**: delete at a fixed instant the holder chose. Using the account does not move it.
- **`inactivity`**: delete when the account has not been used for a number of days.

### What counts as use

Use is the latest use of the account's **personal** and **app** accesses:

- a sign-in, and every call made with the token it issues;
- every call made by an app the holder connected, including one that syncs on a schedule: the holder consented to it and the data is used on their behalf;
- every call made by a [delegate](/guides/account-delegation/) of the account (a caregiver managing it counts as use).

**Shared accesses never count**: a doctor reading shared data, or an integration writing into a shared stream, does not keep an account alive. Neither do failed sign-ins, public methods, webhook deliveries, nor attachment downloads (which are not tracked).

The platform keeps the latest use it has seen, so deleting an access does not make an account look unused for longer.

Inactivity is measured from the access usage tracking (`accessTracking.isActive`, on by default). With tracking off, the `inactivity` trigger is not offered on that core and an inactivity preset refuses to boot; the `date` trigger still works.

### Operator preset

`account.autoDeletion.inactivity.defaultDays` sets a preset: delete accounts unused for that many days. A holder may change it or opt out, unless you forbid it (`userOverride`, `allowUserOptOut`).

- **It applies only to plain accounts with an email address.** Accounts without an address (no reminder could reach them), group accounts (accounts with members) and accounts under a delegation are not covered by a preset. Their holders can still set a schedule themselves.
- **It applies only on a core that sends mail.** Without mail the preset never applies, and the core logs a warning at boot.
- **Its clock starts the first time it applies to an account.** Turning a preset on for a platform with accounts unused for years does not delete them at the next pass: each one gets the full reminder schedule first. Lowering the preset (from 365 to 90 days, say) restarts the clock of the accounts it covers; raising it does not.
- **It is per core.** Configuration is one file per core: for a platform-wide preset, set the same values on every core.
- **It is your storage-limitation rule.** When you set `defaultDays`, your privacy notice must say so: the period, and what counts as use of an account.

A schedule the holder chose takes precedence over the preset; `mode: "default"` brings the account back to it.

### Reminders and minimum notice

Reminders are mailed to the account's primary email address `reminders.leadDays` before the deletion (by default 60, 30, 7 and 1 day before). A reminder whose lead is not shorter than the period is dropped (a 45-day period gets the 30, 7 and 1-day ones). They link to the account app, to change or cancel the schedule, and to its data page, to download the data before the deletion.

- **In `inactivity` mode, signing in postpones the deletion.** Any use moves the deadline, and the reminder schedule starts again. There is no "keep my account" link in the mails: signing in does that.
- **Each reminder is sent once per deadline.** A deadline that moves by less than a day (the normal jitter of an account in use) keeps the schedule.
- **After downtime, only the most imminent overdue reminder is sent**, never a burst.
- **Minimum notice.** No account is deleted less than `reminders.minNoticeDays` (default 7) after the first notice actually sent to it; the deletion waits. The confirmation mail of a holder's setting counts as the first notice. A mail that cannot be delivered is retried at the next pass, and the deletion waits for it.

An account that cannot receive mail is handled explicitly: a holder setting a schedule on it must acknowledge that no reminder will come (`acknowledgeNoReminders`). If the address is removed later, a schedule set without that acknowledgement is held (`blocked: { reason: "no-email" }`) until an address is set again.

### The deletion sweep

Each core runs one sweep, in one of its API workers, every `sweepIntervalMs` (default every 6 hours). No cluster coordination is needed: an account lives on one core. For each account with a schedule, a pass:

1. computes the latest use and the deadline, and sends the reminders that are due;
2. when the account is due, reads its latest use again (a sign-in may have just happened);
3. runs the same checks as a direct account deletion. When one refuses (for example, the account controls a delegated account that has no email address of its own), the schedule is held (`blocked`), the holder is mailed once, and the check is retried at each pass without further mail;
4. deletes the account exactly as a direct deletion does: its data, attachments, high-frequency series and accesses, its delegations and cross-account relationships (the counterparties are notified), and its audit log according to `audit.onUserDelete`.

Safeguards:

- **`dryRun: true`** makes the sweep log the reminders it would send and the accounts it would delete, and do neither. Run it first when you set a preset on a platform with dormant accounts, to see the numbers.
- **`maxDeletionsPerPass`** (default 20) caps the deletions of one pass; the rest wait for the next. It limits the damage of a configuration mistake.
- A pass still running when the next is due is not doubled.
- An erasure interrupted halfway (a crash, a failed step) is completed at the next pass.
- Each deletion is logged at warning level before it starts and once it is done (username, trigger, whether the policy was the holder's or the platform's, deadline, when the notices were sent; never an email address). With `audit.onUserDelete: keep`, an audit record of the deletion is kept as well. With the default `erase`, the log line is what remains.

There is no grace period after the deadline: the 1-day last notice, the minimum notice, the per-pass cap and the dry run are the safeguards. A holder who comes back before the deadline only needs to sign in.

## Configuration

The block lives in the per-core `account` section of `override-config.yml`. Values shown are the defaults.

```yaml
account:
  autoDeletion:
    enabled: true
    dryRun: false
    inactivity:
      defaultDays: null
      minDays: 90
      maxDays: 3650
    userOverride: true
    allowUserOptOut: true
    date:
      minLeadDays: 14
    reminders:
      leadDays: [60, 30, 7, 1]
      minNoticeDays: 7
    sweepIntervalMs: 21600000
    maxDeletionsPerPass: 20
```

| Key | Default | Meaning |
|---|---|---|
| `enabled` | `true` | `false` hides the feature (`features.autoDeletion` is absent, both methods answer `unavailable-method`) and stops the sweep: nothing is deleted. |
| `dryRun` | `false` | `true`: the sweep logs what it would send and delete, and does neither. |
| `inactivity.defaultDays` | `null` | The operator preset, in days. `null`: no preset, accounts are never deleted unless their holder asks. |
| `inactivity.minDays` / `maxDays` | `90` / `3650` | The periods a holder may choose. |
| `userOverride` | `true` | A holder may choose a date or a period (and so change the preset). `false`: holders can only follow the platform's policy or, if allowed, opt out. With no preset either, the feature does nothing. |
| `allowUserOptOut` | `true` | A holder may set `never` while the preset covers the account. `false` enforces the preset as a retention rule. |
| `date.minLeadDays` | `14` | How far from now, in days, a chosen date must at least be. |
| `reminders.leadDays` | `[60, 30, 7, 1]` | Days before the deletion the reminders are sent; positive whole numbers, strictly decreasing. |
| `reminders.minNoticeDays` | `7` | Minimum days between the first notice and the deletion; at least 1, and not more than `date.minLeadDays`. |
| `sweepIntervalMs` | `21600000` (6 h) | How often the sweep runs; at least `60000` (1 min). |
| `maxDeletionsPerPass` | `20` | Deletions per pass at most; `0` = no limit. |

The `transfer.*` keys of the block (`claimWindowDays`, `identitySecretsKey`) belong to the transfer action, which is not offered yet; leave them at their defaults.

**Boot checks** (also run offline by `node bin/check-config.js <your-config.yml>`): `minDays <= defaultDays <= maxDays`, valid `leadDays`, `minNoticeDays` between 1 and `minLeadDays`. A preset with `accessTracking.isActive: false` refuses to boot (inactivity could not be measured). A preset on a core without mail, or without `service.account` (the account app the mails link to), boots with a warning.

### Self-deletion (`user-account.delete`)

A holder can schedule the deletion of their account only where they could delete it directly: `user-account.delete` must list `personalToken`. The shipped default lists `adminToken` only; there, `features.autoDeletion.actions` is empty and holders cannot set a date or a period (`auto-deletion-action-not-allowed`), though they can still set `never`. An operator preset is your own act and is not bound by this setting.

```yaml
user-account:
  delete:
    - 'adminToken'
    - 'personalToken'   # lets holders delete their account, and schedule its deletion
```

### What holders cannot do

- **A delegate cannot set it.** A [delegate](/guides/account-delegation/) can read the schedule but not change it: only the account's own sign-in can, as for detaching a delegate.
- **Arming or shortening needs the password.** Setting a schedule, or bringing the deletion nearer, requires the account password, counted like a sign-in attempt. Clearing it or moving it later does not.

## Mails

| Mail | Sent when | Template | Switch |
|---|---|---|---|
| **Confirmation** | the holder changes the setting, clearing included; it names the deadline, or says nothing is scheduled | `account-deletion-scheduled` | `services.email.enabled.accountDeletionScheduled` |
| **Reminder** | at each `reminders.leadDays` before the deletion | `account-deletion-reminder` | `services.email.enabled.accountDeletionReminder` |
| **Deletion held** | a check refused the deletion (sent once) | `account-deletion-blocked` | `services.email.enabled.accountDeletionBlocked` |

All are on by default, go to the account's primary address in its language (else `services.email.defaultLang`), and are skipped when the account has no address or the core sends no mail. A failed confirmation never fails the holder's change; with the confirmation switched off, the first reminder is the first notice. The template names can be changed with `services.email.accountDeletionScheduledTemplate`, `accountDeletionReminderTemplate` and `accountDeletionBlockedTemplate`.

The templates get these variables:

| Variable | Value |
|---|---|
| `USERNAME` | the account's username |
| `DEADLINE` | date and time of the deletion (UTC), `''` when none is scheduled |
| `DAYS_LEFT` | days left before the deletion |
| `TRIGGER` | `date`, `inactivity`, or `none` (nothing scheduled) |
| `SCHEDULED`, `TRIGGER_DATE`, `TRIGGER_INACTIVITY` | `'true'` or `''`, for conditionals in the template |
| `INACTIVITY_DAYS` | the period, with the `inactivity` trigger |
| `ACTION` | `delete` |
| `ACCOUNT_APP_URL` | `service.account` |
| `EXPORT_URL` | the account app's data page, to download the data before the deletion |

**Existing platforms must add the templates.** The bundled templates (en, fr) are seeded only into an empty PlatformDB, on a platform's first boot. A platform seeded before this feature adds them with `bin/mail.js templates set` (or the admin API), per language and part; the bundled sources are in `components/mail/templates/` of open-pryv.io:

```sh
node bin/mail.js templates set account-deletion-scheduled en subject --file components/mail/templates/account-deletion-scheduled/en/subject.pug
node bin/mail.js templates set account-deletion-scheduled en html --file components/mail/templates/account-deletion-scheduled/en/html.pug
# same for fr, and for account-deletion-reminder and account-deletion-blocked
```

See [Managing templates](/customer-resources/emails-setup/#managing-templates--binmailjs-cli-) for the CLI and the admin API.
