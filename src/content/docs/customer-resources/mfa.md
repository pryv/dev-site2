---
title: 'Pryv.io Multi-Factor Authentication configuration'
---


This document describes how to configure Multi-Factor Authentication (MFA) for the Pryv.io [auth.login](/reference/#login-user) API method.

> **Since v2 (2026)** MFA is built into the core binary (merged from the standalone `service-mfa` process). There is no separate MFA container, no `platform.yml`, no admin-panel tab — the configuration lives under `services.mfa.*` in `override-config.yml`, applied on core restart. MFA (authenticator-app TOTP) is **enabled by default** and works out of the box with no configuration; set `services.mfa.active: false` to disable it. Nothing is forced on users (login only challenges accounts that have enrolled).

> **Multi-method (2026-09).** MFA now supports two methods: an **authenticator app (TOTP, RFC 6238)** and **SMS** (or any HTTP message provider). When you enable MFA, **TOTP is the default method** and runs entirely in-process — no external service required. SMS still works exactly as before. The modern config shape is `services.mfa.active` + `services.mfa.defaultMethod` + `services.mfa.methods.{totp,sms}` (see [Configuration](#configuration)); the legacy single-valued `services.mfa.mode` is still honoured (it is shimmed onto `methods.sms`), so existing SMS deployments need no change. With the in-process TOTP factor a deployment can claim NIST SP 800-63B **AAL2** without a third-party service.

The prerequisite for this is to have:

- a running Pryv.io v2+ instance;
- for **TOTP**: nothing else — codes are generated on the user's device (Google Authenticator, 1Password, etc.) and verified in-process;
- for **SMS**: an external communication service to send messages over another channel (SMS or email).

The `mfa.*` API flow (activate → confirm → login → challenge → verify) is the same for both methods; only the enrolment payload and what is verified differ. For SMS, depending on your provider's capabilities you use the **single** or **challenge-verify** mode.


## Table of contents <!-- omit in toc -->

1. [Flow](#flow)
   1. [Setup](#setup)
   2. [Usage](#usage)
   3. [Deactivation and recovery](#deactivation-and-recovery)
2. [Modes](#modes)
3. [Configuration](#configuration)
   1. [Enabling MFA](#enabling-mfa)
   2. [Endpoint shape](#endpoint-shape)
   3. [User data](#user-data)
   4. [Parameters](#parameters)
      1. [url](#url)
      2. [method](#method)
      3. [body](#body)
      4. [headers](#headers)
   5. [Session TTL](#session-ttl)
4. [Single](#single)
   1. [Single template](#single-template)
   2. [Single user data](#single-user-data)
5. [Challenge-Verify mode](#challenge-verify-mode)
   1. [Challenge-Verify template](#challenge-verify-template)
   2. [Challenge-Verify user data](#challenge-verify-user-data)
6. [References](#references)


## Flow

You will need to define a template for the API call(s) that will be made to your communication service. The user-specific values that will be substituted in the template will be stored in the user's [private profile](/reference/#get-private-profile).

### Setup

MFA must be activated per user account. You can implement this in your onboarding flow or at a later time.
After obtaining a `personal` token from an [auth.login](/reference/#login-user) API call, you must call the [activate MFA](/reference/#activate-mfa) API method, providing the user's MFA data. This will trigger the challenge sent to the user.

You should [confirm MFA activation](/reference/#confirm-mfa-activation) by sending the obtained challenge in the payload which will be substituted in the related template. If confirmation is successful, the MFA data provided at activation is saved in the user's [private profile](/reference/#get-private-profile), alongside `recoveryCodes` which you receive for [later deactivation](#deactivation-and-recovery).

### Usage

Once MFA has been activated for an account, you will receive a `mfaToken` each time you perform a [Login user](/reference/#login-with-mfa) API call. You will use it to [Trigger the MFA challenge](/reference/#trigger-mfa-challenge) where data saved in the [private profile](/reference/#get-private-profile) will be sent to your communication service.
You will send the received challenge the same way you did for confirmation, but this time using the [verify MFA challenge](/reference/#verify-mfa-challenge) route.

### Deactivation and recovery

You may deactivate MFA using a personal token on the [deactivate MFA](/reference/#deactivate-mfa) API method. If you have lost access to your 2nd factor such as phone or email, you can also use the [recover MFA](/reference/#recover-mfa) route to deactivate it using one of the recovery codes.


## Modes

The **single** mode is meant when your communication service only supports sending messages. If it supports creating a challenge and verifying it, you can also use **challenge-verify**.

In **single** mode, Pryv.io generates a secret code, sends it to your communication service upon [activation](/reference/#activate-mfa) and [challenge](/reference/#trigger-mfa-challenge), then verifies it itself during [confirmation](/reference/#confirm-mfa-activation) and [verification](/reference/#verify-mfa-challenge).

In **challenge-verify** mode, Pryv.io makes an HTTP request to your communication service to generate and send a code then forwards it during verification.

The templates are set in `override-config.yml` under `services.mfa.sms.endpoints.*`.


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
      ttlSeconds: 1800
```

**Flow.** Call [activate MFA](/reference/#activate-mfa) with a personal token and `{ "method": "totp" }`. The response carries the `mfaToken` plus an `otpauthUri` (render it as a QR code) and the Base32 `secret` (for manual entry). The user adds it to their authenticator app and you [confirm activation](/reference/#confirm-mfa-activation) with the first 6-digit code; you receive the `recoveryCodes`. At [login](/reference/#login-with-mfa) the response includes `mfaMethod: "totp"` next to the `mfaToken` so your UI prompts for an app code; [verify](/reference/#verify-mfa-challenge) it. There is no challenge to send for TOTP (the code is on the user's device), so [trigger MFA challenge](/reference/#trigger-mfa-challenge) is a no-op that just echoes the method.

**Security notes.** TOTP secrets are stored encrypted at rest; a used code cannot be replayed; repeated wrong codes invalidate the pending MFA session; enrolment fails closed if no `secretsKey`/`adminAccessKey` is available. Server clocks should be NTP-synchronised (the `driftSteps` window absorbs small skew).


## Configuration

### Enabling MFA

> This section covers **SMS**. For the default authenticator-app method see [Authenticator app (TOTP)](#authenticator-app-totp) above. To offer SMS under the modern config model, set `services.mfa.methods.sms.active: true` with `methods.sms.mode` + `methods.sms.endpoints` (the legacy top-level `services.mfa.mode` + `services.mfa.sms.endpoints` shown below is still honoured via a shim).

Pick a mode — `single` or `challenge-verify` — and fill in the matching endpoint:

```yaml
services:
  mfa:
    mode: single           # or: challenge-verify | disabled
    sms:
      endpoints:
        # Define only the endpoints matching your chosen mode.
        # Leave the others as empty strings to keep config-validation happy.
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
    sessions:
      ttlSeconds: 1800
```

With `services.mfa.active: false` the MFA API methods return a "not enabled" error — for deployments that don't want two-factor authentication at all. (The legacy `mode: disabled` reaches the same off state.)

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

### User data

When activating MFA for a user account, variables provided in the request body at [activation](/reference/#activate-mfa) will be saved in the user's account. They look like this:

```json
{
  "language": "en",
  "phone": "41791231212"
}
```

### Parameters

#### url

You can provide the URL, with the query parameters here as a string. Variables are substituted in the string.

#### method

The HTTP method, currently supports HTTP `POST` and `GET` methods.

#### body

The request body that will be sent, provided as a string. Variables are substituted in the string.

#### headers

The request headers that will be sent in the HTTP request. Variables are substituted in the values of these headers.
As the request body is a string, you will have to provide the corresponding `content-type` header.

### Session TTL

`services.mfa.sessions.ttlSeconds` controls how long a pending challenge stays valid before expiring (default: 1800 seconds / 30 minutes). Sessions are kept in-process (per-core, in-memory) and do not survive a core restart — users in the middle of an MFA challenge at restart time will need to re-trigger.


## Single

For **single** mode, you can provide a `{{ code }}` variable which will be substituted with a code generated by Pryv.io.
The example hereafter stores the message in the user-specific data, where `{{ code }}` substitution also works.

### Single template

The configuration for single mode describes the HTTP request made by Pryv.io during [activation](/reference/#activate-mfa) and [challenge](/reference/#trigger-mfa-challenge):

```yaml
services:
  mfa:
    mode: single
    sms:
      endpoints:
        single:
          url: 'https://api.smsmode.com/http/1.6/sendSMS.do?accessToken=your-api-key&message={{ message }}&emetteur=Pryv%20Lab&numero={{ number }}'
          method: 'GET'
```

### Single user data

with the following user data sent during [activation](/reference/#activate-mfa):

```json
{
  "number": "41791231212",
  "message": "Your%20Pryv%20Lab%20MFA%20code%20is%3A%20{{ code }}"
}
```

Note that the message `Your Pryv Lab MFA code is: {{ code }}` has been URL-encoded as it will appear in query parameters, but the `{{ code }}` variable is kept as-is since it must be substituted by Pryv.io.

and [confirmation](/reference/#confirm-mfa-activation) / [verification](/reference/#verify-mfa-challenge):

```json
{
  "code": "12345"
}
```


## Challenge-Verify mode

### Challenge-Verify template

The configuration for challenge-verify mode describes two HTTP requests — `challenge` is made during [activation](/reference/#activate-mfa) and [trigger](/reference/#trigger-mfa-challenge); `verify` is made during [confirmation](/reference/#confirm-mfa-activation) and [verification](/reference/#verify-mfa-challenge):

```yaml
services:
  mfa:
    mode: challenge-verify
    sms:
      endpoints:
        challenge:
          url: 'https://api.smsapi.com/mfa/codes'
          method: 'POST'
          body: '{"phone_number":"{{ number }}"}'
          headers:
            authorization: 'Bearer: your-api-key'
            'content-type': 'application/json'
        verify:
          url: 'https://api.smsapi.com/mfa/codes/verifications'
          method: 'POST'
          body: '{"phone_number":"{{ number }}","code":"{{ code }}"}'
          headers:
            authorization: 'Bearer: your-api-key'
            'content-type': 'application/json'
```

### Challenge-Verify user data

with the following user data sent during [activation](/reference/#activate-mfa):

```json
{
  "number": "41791231212"
}
```

and [confirmation](/reference/#confirm-mfa-activation) / [verification](/reference/#verify-mfa-challenge):

```json
{
  "code": "12345"
}
```


## References

The aforementioned examples use working templates and user data for:

- SMS API: [https://www.smsapi.com/docs/#15-sms-authenticator](https://www.smsapi.com/docs/#15-sms-authenticator)
- SMS mode: [https://www.smsmode.com/api-sms/](https://www.smsmode.com/api-sms/)
