---
title: 'Account auto-deletion'
description: How a Pryv.io platform deletes accounts, or hands them over to a beneficiary, at a date their holder chose or after a period without use, with reminder mails, a minimum notice and an optional operator preset. Settings, safeguards, mail templates and what the holder sees.
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

| `transfer.claimWindowDays` | `90` | How long a beneficiary has to claim an account once its transfer starts (see [Transfer to a beneficiary](#transfer-to-a-beneficiary)). |
| `transfer.identitySecretsKey` | `null` | Key (base64, 32 bytes; YAML only, like other secrets) encrypting the beneficiaries' names and dates of birth and deriving the claim and decline links. `null`: derived from `auth.adminAccessKey`. |

**Rotating the key.** With `identitySecretsKey: null`, rotating `auth.adminAccessKey` makes the stored names and dates of birth unreadable and the claim and decline links already mailed invalid. Set a dedicated `identitySecretsKey` before you rely on transfers if you rotate the admin key; changing the dedicated key has the same effect.

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
- **Choosing who gets the account needs the password.** Setting or changing a transfer (the beneficiary, the fallback, the notice, a name or a date of birth) requires it too, and so does turning a transfer into a deletion.

## Transfer to a beneficiary

Instead of a deletion, a holder may choose `action: transfer`: at the date, or after the period without use, the account is handed over to a beneficiary, who becomes its **controller** through [account delegation](/guides/account-delegation/) and manages it from their own account. The holder's sign-in is left as it is. A platform preset always deletes; a transfer is always the holder's own choice.

**Offered where it can work:** account delegation on (`delegation.active`), mail configured, and `service.account` set (the claim and decline pages are pages of the account app). `features.autoDeletion.actions` then lists `transfer`. Where holders may not delete their account (`user-account.delete`), a transfer is still offered, with `keep` as the only fallback.

**What the holder gives:**

- the beneficiary's **email address** (required): the beneficiary is reached by mail only;
- optionally their **name** and **date of birth**: used only if the email cannot reach the beneficiary, by you, the operator, to check the identity of a person who asks for the account. They are stored encrypted in their own account field, never returned by the API (not even to the holder), and erased, with every earlier version, when the transfer completes, is cancelled, declined or lapses, when the beneficiary changes, and with the account. The account app shows the holder this notice next to the two fields. **No reading method is shipped yet:** nothing can read them for now. When one is, the notice promises that every reading is logged and reported to the holder's address, and that you read them only after the transfer started;
- when to tell the beneficiary: **at setup** (`atSetup`: mailed at once, with a link to decline) or only **when the transfer starts** (`atTrigger`);
- the **fallback** if nobody claims it: `delete` (only where the holder may delete the account) or `keep`.

**When it is due,** the sweep opens a **claim window** of `transfer.claimWindowDays` days instead of erasing: the beneficiary is mailed a claim link (sent again 30 and 60 days later, the same link), and the holder is told. The reminders before it say "will be transferred to". In `inactivity` mode, a use of the account before anyone claims it (the holder's, or a delegate's) cancels the transfer: both are mailed and the clock starts again. In `date` mode the holder cancels it in the account app.

**The claim.** The link opens the account app's claim page. The beneficiary signs in to their own account on the platform (any core), or creates one, and accepts: the page calls [`account.transferClaim`](/reference/#methods-account-account-transferClaim) on the holder's core, which binds the transfer to that account and sends it a delegation invite on the holder's behalf; the page accepts the invite on the beneficiary's core and claims again, which completes the transfer. The holder's auto-deletion setting is then cleared (a new schedule needs the holder's own sign-in) and both are mailed. Possession of the link is the proof of being the beneficiary; the name and date of birth are never asked. The first account to claim is the only one that can; a claim with a wrong link counts on the address's budget of failed secrets (`auth.passwordAttempts.perIp`), and after ten failed claims of one transfer, claims are refused until the next sweep pass (the holder sees it in the app).

**At the end of the window without a claim,** the fallback applies: `keep` leaves the account (the holder's setting becomes `never`, or your preset where opting out is not allowed, with its full reminder schedule from that day); `delete` erases it as a scheduled deletion would, through the same checks (deletion guards, self-deletion, `maxDeletionsPerPass`), recorded with the trigger `transfer-fallback`. A beneficiary who declines makes the fallback apply at once (before the deadline: the schedule becomes a deletion, or `never`).

**Data protection.** The beneficiary's address, and their name and date of birth when given, are personal data of someone who did not give them to you; the beneficiary mails tell them who named them and on what terms. Whether a notice only when the transfer starts (`atTrigger`) is enough for your jurisdiction is a question for your data protection officer.

## Mails

| Mail | Sent when | Template | Switch |
|---|---|---|---|
| **Confirmation** | the holder changes the setting, clearing included; it names the deadline, or says nothing is scheduled | `account-deletion-scheduled` | `services.email.enabled.accountDeletionScheduled` |
| **Reminder** | at each `reminders.leadDays` before the deletion | `account-deletion-reminder` | `services.email.enabled.accountDeletionReminder` |
| **Deletion held** | a check refused the deletion (sent once) | `account-deletion-blocked` | `services.email.enabled.accountDeletionBlocked` |
| **Beneficiary named** | to the beneficiary, when named with `atSetup` (with a decline link) | `account-transfer-named` | `services.email.enabled.accountTransferNamed` |
| **Claim link** | to the beneficiary, when the claim window opens, and again 30 and 60 days later | `account-transfer-claim` | `services.email.enabled.accountTransferClaim` |
| **Transfer started** | to the holder, when the claim window opens | `account-transfer-started` | `services.email.enabled.accountTransferStarted` |
| **Transfer cancelled** | to the holder and the beneficiary: the account was used, the holder changed it, or the beneficiary declined | `account-transfer-cancelled` | `services.email.enabled.accountTransferCancelled` |
| **Transfer lapsed** | to the holder, when the window ends without a claim and the account is kept | `account-transfer-lapsed` | `services.email.enabled.accountTransferLapsed` |
| **Transfer completed** | to the holder and the beneficiary | `account-transfer-completed` | `services.email.enabled.accountTransferCompleted` |

Keep the beneficiary named and claim link mails on wherever transfers are offered: without them a transfer cannot reach its beneficiary.

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
| `ACTION` | `delete` or `transfer` |
| `ACCOUNT_APP_URL` | `service.account` |
| `EXPORT_URL` | the account app's data page, to download the data before the deletion |
| `ACTION_TRANSFER` | `'true'` for a transfer, else `''` |
| `BENEFICIARY` | the beneficiary's name if the holder gave one, else their address (in the beneficiary's own mails: always the address) |
| `BENEFICIARY_EMAIL`, `BENEFICIARY_NAME` | the two separately (`BENEFICIARY_NAME` is never sent to the beneficiary) |
| `FALLBACK_DELETE`, `FALLBACK_KEEP`, `IDENTITY_GIVEN`, `NOTIFY_AT_SETUP` | `'true'` or `''` |

The transfer mails also get `OPERATOR_NAME` (`service.name`), `TO_BENEFICIARY` (`'true'` in the beneficiary's copy), `CLAIM_LINK` and `DECLINE_LINK` (pages of the account app, `''` when not usable), `WINDOW_END` and `WINDOW_DAYS`, `CLAIMANT` (the account that claimed it), and `REASON` (`declined`, `owner-activity`, `delegate-activity`, `owner-change`) with one flag each (`REASON_DECLINED`, ...).

**Existing platforms must add the templates.** The bundled templates (en, fr) are seeded only into an empty PlatformDB, on a platform's first boot. A platform seeded before this feature adds them with `bin/mail.js templates set` (or the admin API), per language and part; the bundled sources are in `components/mail/templates/` of open-pryv.io:

```sh
node bin/mail.js templates set account-deletion-scheduled en subject --file components/mail/templates/account-deletion-scheduled/en/subject.pug
node bin/mail.js templates set account-deletion-scheduled en html --file components/mail/templates/account-deletion-scheduled/en/html.pug
# same for fr, and for account-deletion-reminder and account-deletion-blocked;
# with transfers: the six account-transfer-* templates, and again
# account-deletion-scheduled and account-deletion-reminder (they now say "transferred to")
```

See [Managing templates](/customer-resources/emails-setup/#managing-templates--binmailjs-cli-) for the CLI and the admin API.
