---
title: 'Pryv.io Multi-Factor Authentication configuration'
description: How to configure Multi-Factor Authentication for Pryv.io login, covering the default in-process TOTP authenticator app and SMS-based verification.
---


This document describes how to configure Multi-Factor Authentication (MFA) for the Pryv.io [auth.login](/reference/#login-user) API method.

> **Since v2 (2026)** MFA is built into the core binary (merged from the standalone `service-mfa` process). There is no separate MFA container, no `platform.yml`, no admin-panel tab: the configuration lives under `services.mfa.*` in `override-config.yml`, applied on core restart. MFA (authenticator-app TOTP) is **enabled by default** and works out of the box with no configuration; set `services.mfa.active: false` to disable it. Nothing is forced on users (login only challenges accounts that have enrolled).

> **Multi-method (2026-09).** MFA now supports two methods: an **authenticator app (TOTP, RFC 6238)** and **SMS** (or any HTTP message provider). When you enable MFA, **TOTP is the default method** and runs entirely in-process, with no external service required. The modern config shape is `services.mfa.active` + `services.mfa.defaultMethod` + `services.mfa.methods.{totp,sms}` (see [Configuration](#configuration)); the legacy single-valued `services.mfa.mode` is still honoured (it is shimmed onto `methods.sms`). With the in-process TOTP factor a deployment can claim NIST SP 800-63B **AAL2** without a third-party service.

The prerequisite for this is to have:

- a running Pryv.io v2+ instance;
- for **TOTP**: nothing else; codes are generated on the user's device (Google Authenticator, 1Password, etc.) and verified in-process;
- for **SMS**: an external communication service to send messages over another channel (SMS or email).

The `mfa.*` API flow (activate → confirm → login → challenge → verify) is the same for both methods; only the enrolment payload and what is verified differ. For SMS, depending on your provider's capabilities you use the **single** or **challenge-verify** mode.

## Flow

For SMS, you define a template for the API call(s) made to your communication service. The user-specific values substituted in the template (the enrolment content: the phone number and the keys you allow) are stored in the user's [private profile](/reference/#get-private-profile).

### Setup

MFA must be activated per user account. You can implement this in your onboarding flow or at a later time.
After obtaining a `personal` token from an [auth.login](/reference/#login-user) API call, you must call the [activate MFA](/reference/#activate-mfa) API method, providing the user's MFA data. For SMS, this sends the first code. The account must log in itself: a delegated personal access ([account delegation](/guides/account-delegation/)) cannot change MFA.

You should [confirm MFA activation](/reference/#confirm-mfa-activation) by sending the code the user received (or read in the authenticator app). If confirmation is successful, the enrolment is saved in the user's [private profile](/reference/#get-private-profile), and you receive the `recoveryCodes` for [later deactivation](#deactivation-and-recovery) (they are stored hashed). Reading the private profile shows the enrolment without its secrets (`mfa: { method, content, totp: { confirmedAt, algorithm, digits, periodSeconds } }`); the enrolment cannot be changed through profile updates, only through the MFA methods.

An account has at most one pending activation: a new [activate MFA](/reference/#activate-mfa) call invalidates the previous one's `mfaToken`. Activating over an **active** enrolment replaces it and requires a [step-up](#step-up).

### Usage

Once MFA has been activated for an account, you will receive a `mfaToken` (and the `mfaMethod`) each time you perform a [Login user](/reference/#login-with-mfa) API call. For SMS, the login sends a code; [Trigger the MFA challenge](/reference/#trigger-mfa-challenge) sends a new one if needed.
You then send the code with the [verify MFA challenge](/reference/#verify-mfa-challenge) route to receive the personal token.

### Deactivation and recovery

You may deactivate MFA using a personal token of the account's own login on the [deactivate MFA](/reference/#deactivate-mfa) API method, with a [step-up](#step-up). If you have lost access to your 2nd factor such as phone or email, you can also use the [recover MFA](/reference/#recover-mfa) route to deactivate it using one of the recovery codes.

### Step-up

Turning MFA off, and replacing an active enrolment, weaken the account's second factor, so a personal token alone is not enough: the request body must also carry either `password` (the account password) or `code` (a current code of the account's authenticator app, accepted once). An SMS enrolment steps up with the password, since no code is sent for a step-up.

- Neither of the two, or both: `400 invalid-parameters-format` with `error.data.id: 'step-up-required'`.
- A wrong one: `403 invalid-step-up`. It counts as a failed attempt in the account's [backoff](#authenticator-app-totp), and while a delay runs the step-up is not checked (`429 too-many-attempts`).
- The body of [deactivate MFA](/reference/#deactivate-mfa) is validated: a key other than `password` or `code` is refused (`400`).

```yaml
services:
  mfa:
    stepUp:
      required: true   # PLATFORM-WIDE: set the same value on every core
```

`required: false` restores the former behaviour (a personal token alone) and logs a warning at every boot. It is a migration opt-out for one release, for clients not yet sending the step-up, and will be removed in a later release.

### Change notices

When mail is configured, the account's email address receives a notice when its MFA is enrolled, replaced, deactivated, removed with a recovery code or reset by the administrator (template `mfa-change`, switch `services.email.enabled.mfaChange`). See [MFA change notice](/customer-resources/emails-setup/#mfa-change-notice).

### Accounts whose method is not active

An account enrolled in a method that this server does not have active (for example an SMS enrolment after the legacy `mode` was removed without activating `methods.sms`) cannot log in: the login answers `403 mfa-method-inactive`, before any session or personal access is written, and the refusal is logged as a warning (at most once per user every 10 minutes). With the PostgreSQL engine, the boot also warns when the core holds SMS enrolments while SMS is not active.

```yaml
services:
  mfa:
    allowLoginWhenMethodInactive: false   # PLATFORM-WIDE: set the same value on every core
```

`true` restores the former behaviour: these accounts log in with the password only, without a second factor, and a warning is logged at each such login and at boot. Prefer activating the method they are enrolled in.


## Modes

The **single** mode is meant when your communication service only supports sending messages. If it supports creating a challenge and verifying it, you can also use **challenge-verify**.

In **single** mode, Pryv.io generates a secret code, sends it to your communication service upon [activation](/reference/#activate-mfa), login and [challenge](/reference/#trigger-mfa-challenge), then verifies it itself during [confirmation](/reference/#confirm-mfa-activation) and [verification](/reference/#verify-mfa-challenge).

In **challenge-verify** mode, Pryv.io makes an HTTP request to your communication service to generate and send a code then forwards it during verification.

The templates are set in `override-config.yml` under `services.mfa.methods.sms.endpoints.*` (or the legacy `services.mfa.sms.endpoints.*`).


## Authenticator app (TOTP)

TOTP (RFC 6238) is the **default method** when MFA is enabled and needs **no external service**: Pryv.io generates the shared secret, the user scans it into an authenticator app, and codes are verified in-process.

Enable it and make it the default:

```yaml
services:
  mfa:
    active: true
    defaultMethod: totp
    methods:
      totp:
        active: true
        issuer: ''          # otpauth issuer label shown in the app; '' => your dns.domain
        digits: 6
        periodSeconds: 30
        driftSteps: 1       # accept codes +/- N 30s steps around now
        # At-rest key for the stored TOTP secrets (AES-256-GCM). Leave empty to
        # derive it from auth.adminAccessKey (rotating that key invalidates
        # enrolments); set a dedicated base64 32-byte key for independent rotation.
        secretsKey: ''
      sms:
        active: false       # optionally offer SMS as well (see below)
    sessions:
      ttlSeconds: 1800      # lifetime of a pending MFA session, fixed when it opens
      maxPending: 10000     # most pending MFA sessions per core; 0 disables the cap
    attempts:
      perSession: 5         # wrong codes allowed in one pending MFA session
      perAccountWindowSeconds: 900   # a failure older than this starts the tally afresh
      backoff:              # per-account delay after repeated failures, never a lockout
        freeFailures: 3     # failures before any delay
        baseSeconds: 2      # first delay, doubling on each further failure
        maxSeconds: 300     # cap; 0 disables the per-account backoff
    stepUp:
      required: true        # see Step-up
    allowLoginWhenMethodInactive: false   # see Accounts whose method is not active
```

**Flow.** Call [activate MFA](/reference/#activate-mfa) with a personal token and `{ "method": "totp" }` (no other enrolment parameter is accepted). The response carries the `mfaToken` plus an `otpauthUri` (render it as a QR code) and the Base32 `secret` (for manual entry). The user adds it to their authenticator app and you [confirm activation](/reference/#confirm-mfa-activation) with the first 6-digit code; you receive the `recoveryCodes`. At [login](/reference/#login-with-mfa) the response includes `mfaMethod: "totp"` next to the `mfaToken` so your UI prompts for an app code; [verify](/reference/#verify-mfa-challenge) it. There is no challenge to send for TOTP (the code is on the user's device), so [trigger MFA challenge](/reference/#trigger-mfa-challenge) is a no-op that just echoes the method.

**Security notes.** TOTP secrets are stored encrypted at rest; a used code cannot be replayed, even when the same code is submitted twice at the same moment; enrolment fails closed if no `secretsKey`/`adminAccessKey` is available. Server clocks should be NTP-synchronised (the `driftSteps` window absorbs small skew).

Wrong codes are limited twice. `perSession` wrong codes invalidate the pending MFA session, so the user logs in again. Failures also accrue on the account across logins (wrong [step-ups](#step-up) included): past `backoff.freeFailures` of them, each further failure delays the next attempt, doubling from `baseSeconds` up to `maxSeconds`. During a delay the MFA endpoints answer `429 too-many-attempts` with a `Retry-After` header and `error.data.retryAfterSeconds`, and a code sent then is not checked. This is a delay, never a lockout: someone who knows the password cannot lock the real user out, who waits at most `maxSeconds`, and a successful second factor clears the tally. The `attempts` block is platform-wide policy: set the same values on every core. Settings that cannot work (an unknown `defaultMethod`, a malformed `secretsKey`, out-of-range TOTP parameters, SMS without its endpoints) stop the core at boot with the key named.


## Configuration

### Enabling MFA

> This section covers **SMS**. For the default authenticator-app method see [Authenticator app (TOTP)](#authenticator-app-totp) above.

Activate SMS under `services.mfa.methods.sms`, pick a mode (`single` or `challenge-verify`) and fill in the matching endpoints:

```yaml
services:
  mfa:
    active: true
    methods:
      sms:
        active: true
        mode: single           # or: challenge-verify
        contentKeys: []        # enrolment keys accepted besides `phone`, e.g. [language]
        codeLength: 6          # single mode: digits of the code (4 to 10)
        codeTtlSeconds: 300    # single mode: how long a code is accepted
        sendLimits:            # both modes; 0 disables a limit (with a boot warning)
          minIntervalSeconds: 30    # between two sends on one MFA session
          perUserPerHour: 5         # sends per user
          perDestinationPerDay: 10  # sends per phone number, across users
        endpoints:
          # Define only the endpoints matching your chosen mode.
          single:
            url: ''
            method: POST
            body: ''
            headers: {}
          challenge:
            url: ''
            method: POST
            body: ''
            headers: {}
          verify:
            url: ''
            method: POST
            body: ''
            headers: {}
            success: { jsonPath: status, equals: approved }   # challenge-verify, see below
    sessions:
      ttlSeconds: 1800
      maxPending: 10000
```

The legacy shape (`services.mfa.mode: single | challenge-verify` with `services.mfa.sms.endpoints`) is still honoured; it reads `codeLength`, `codeTtlSeconds` and `sendLimits` from the legacy `services.mfa.sms` block first, then from `methods.sms`. `contentKeys` is read from `methods.sms`, else from the legacy `services.mfa.sms` block. Out-of-range values (a `codeLength` outside 4 to 10, a negative limit, a reserved content key, a malformed `success`) stop the core at boot with the key named.

With `services.mfa.active: false` the MFA API methods return a "not enabled" error, for deployments that don't want two-factor authentication at all. (The legacy `mode: disabled` reaches the same off state.)

### Endpoint shape

Each endpoint describes the HTTP request Pryv.io makes to your communication service:

```yaml
url: 'https://api.smsapi.com/mfa/codes?language={{ language }}'
method: 'POST'
body: '{"phone":"{{ phone }}"}'
headers:
  authorization: 'Bearer: YOUR-COMMUNICATION-SERVER-API-KEY'
  'content-type': 'application/json'
```

(This example uses a `language` enrolment key, so it needs `contentKeys: [language]`.)

### User data

The enrolment content is taken from the [activation](/reference/#activate-mfa) request body and saved in the user's account:

- `phone` is required, in **E.164** format: `+` followed by the country code and number (7 to 15 digits, e.g. `+41791234567`);
- any other key must be listed in `services.mfa.methods.sms.contentKeys`, and is refused otherwise; `phone`, `method`, `password` and `code` cannot be listed;
- every value is a string, and the content as a whole is limited to 256 bytes.

```json
{
  "method": "sms",
  "phone": "+41791234567",
  "language": "en"
}
```

The code itself is never part of the enrolment content: `{{ code }}` is provided by Pryv.io (single mode) or taken from the code the user sends (challenge-verify verify).

### Parameters

The placeholders `{{ key }}` of the url, headers and body are substituted with the enrolment content (and `{{ code }}`). The substitution is done once: a substituted value is never expanded again (a value containing `{{ code }}` stays literal). Each value is encoded for where it lands. A placeholder with no value is left as written.

#### url

You can provide the URL, with the query parameters here as a string. Values are URL-encoded (`encodeURIComponent`): write the template with plain placeholders, never pre-encoded values (`+41791234567` is sent as `%2B41791234567`).

#### method

The HTTP method, currently supports HTTP `POST` and `GET` methods.

#### body

The request body that will be sent, provided as a string (or as a YAML object, sent as JSON). Values are encoded according to the body type:

- form-encoded when the endpoint declares `content-type: application/x-www-form-urlencoded`;
- escaped as the content of a JSON string when the endpoint declares a JSON content type, or when the template is JSON text (placeholders sit inside its string literals);
- inserted as is otherwise (plain text);
- for an object body, substituted on its string values, the whole object being serialized to JSON.

#### headers

The request headers that will be sent in the HTTP request. Values are substituted in the header values; a value holding a character outside printable ASCII (a line break included) is refused and nothing is sent.
As the request body is a string, you will have to provide the corresponding `content-type` header.

### Sessions

`services.mfa.sessions.ttlSeconds` sets how long a pending MFA session (between a login or an activation and its verification or confirmation) stays valid (default: 1800 seconds / 30 minutes). The lifetime is fixed when the session opens: attempts and re-sent challenges do not extend it. Sessions do not survive a core restart: users in the middle of an MFA flow at restart time log in (or activate) again.

`services.mfa.sessions.maxPending` caps the pending sessions a core holds in memory (default 10 000; 0 disables the cap). Past it, a login or an activation that needs a session answers `429 too-many-requests` (with `Retry-After`) until sessions complete or expire.

A session's `mfaToken` is valid only under the path of its own account (`/{username}/mfa/...`); presented for another account it is an unknown token (`401 invalid-access-token`). A login session is also refused once the account's enrolment has changed (deactivated, recovered or replaced) since that login.

### SMS codes and send limits

In single mode the code has `codeLength` digits (default 6) and is accepted for `codeTtlSeconds` (default 300). It belongs to one pending session: only its hash is kept, in that session, and a new challenge on the session replaces it and restarts its lifetime. A code is used once.

Every SMS (login, activation, re-sent challenge), in both modes, counts against `sendLimits`: at most one send every `minIntervalSeconds` on one session, `perUserPerHour` sends per user and `perDestinationPerDay` sends per phone number (counted by a hash of the number, across users). A send over a limit is not made and answers `429 too-many-attempts` with `error.data.retryAfterSeconds`. A send counts once reserved, even when the provider then fails.

`mfa.confirm` and `mfa.verify` require `code`, 4 to 10 digits; nothing else of their body reaches the provider.


## Single

For **single** mode, use the `{{ code }}` placeholder in the template: it is substituted with the code generated by Pryv.io. Put the message text in the template itself (the enrolment content holds no message).

### Single template

The configuration for single mode describes the HTTP request made by Pryv.io during [activation](/reference/#activate-mfa), login and [challenge](/reference/#trigger-mfa-challenge):

```yaml
services:
  mfa:
    active: true
    methods:
      sms:
        active: true
        mode: single
        endpoints:
          single:
            url: 'https://api.smsmode.com/http/1.6/sendSMS.do?accessToken=your-api-key&message=Your%20Pryv%20Lab%20MFA%20code%20is%3A%20{{ code }}&emetteur=Pryv%20Lab&numero={{ phone }}'
            method: 'GET'
```

The fixed parts of the message are URL-encoded in the template, since they appear in query parameters; the substituted values (`{{ code }}`, `{{ phone }}`) are encoded by Pryv.io.

### Single user data

with the following user data sent during [activation](/reference/#activate-mfa):

```json
{
  "method": "sms",
  "phone": "+41791231212"
}
```

and [confirmation](/reference/#confirm-mfa-activation) / [verification](/reference/#verify-mfa-challenge):

```json
{
  "code": "123456"
}
```


## Challenge-Verify mode

### Challenge-Verify template

The configuration for challenge-verify mode describes two HTTP requests: `challenge` is made during [activation](/reference/#activate-mfa), login and [trigger](/reference/#trigger-mfa-challenge); `verify` is made during [confirmation](/reference/#confirm-mfa-activation) and [verification](/reference/#verify-mfa-challenge):

```yaml
services:
  mfa:
    active: true
    methods:
      sms:
        active: true
        mode: challenge-verify
        endpoints:
          challenge:
            url: 'https://api.smsapi.com/mfa/codes'
            method: 'POST'
            body: '{"phone_number":"{{ phone }}"}'
            headers:
              authorization: 'Bearer: your-api-key'
              'content-type': 'application/json'
          verify:
            url: 'https://api.smsapi.com/mfa/codes/verifications'
            method: 'POST'
            body: '{"phone_number":"{{ phone }}","code":"{{ code }}"}'
            headers:
              authorization: 'Bearer: your-api-key'
              'content-type': 'application/json'
```

### Verify success rule

A verify succeeds only when your provider answers `2xx` **and** the answer confirms the code:

- with `endpoints.verify.success: { jsonPath, equals }`, the answer must be JSON and its value at `jsonPath` (dot-separated property names, e.g. `status` or `data.result`) must strictly equal `equals` (a string, number or boolean);
- without it, only an **empty** `2xx` answer (e.g. `204`) is a success, and a `2xx` with a body is refused; the boot warns while `success` is missing.

Set `success` to what your provider returns for an accepted code, e.g. `success: { jsonPath: status, equals: approved }` for a provider answering `{"status":"approved"}`.

### Challenge-Verify user data

with the following user data sent during [activation](/reference/#activate-mfa):

```json
{
  "method": "sms",
  "phone": "+41791231212"
}
```

and [confirmation](/reference/#confirm-mfa-activation) / [verification](/reference/#verify-mfa-challenge):

```json
{
  "code": "123456"
}
```


## References

The examples above are modelled on these providers; check their documentation for the exact request format, the phone number format they expect, and the answer to configure as the verify `success` rule:

- SMS API: [https://www.smsapi.com/docs/#15-sms-authenticator](https://www.smsapi.com/docs/#15-sms-authenticator)
- SMS mode: [https://www.smsmode.com/api-sms/](https://www.smsmode.com/api-sms/)
