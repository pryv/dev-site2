---
title: 'Email address verification'
description: How an application proves an email address at sign-up, verifies further addresses on an account, and reads the verification status back, including which provenance values count as proved ownership.
---

## Introduction

A Pryv.io account can hold several email addresses, and each one carries a verification state. Two independent features put that state there:

- **at registration**, the platform can require the address to be proved before the account exists. The holder receives a code and pastes it back;
- **on an account**, an address can be proved afterwards. The holder receives a link and opens it.

Both are operator settings, so the same application code runs against platforms that use neither, one, or both. This guide is for application developers. For the configuration side, which keys turn these on and what they require, see [email configuration](/customer-resources/emails-setup/#email-verification).

## First, ask the platform what it does

Never hard-code the assumption. `GET /service/info` always carries both switches:

```json
{
  "features": {
    "emailVerification": { "atRegistration": true, "onAccount": true }
  }
}
```

| Field | What it means for your app |
|---|---|
| `atRegistration` | `true`: your sign-up form must collect an email address and prove it before calling create user. `false`: the address is optional as before. |
| `onAccount` | `true`: you can offer a "verify this address" action, and a verification mail will actually be sent. `false`: hide the action, since a request would report success while nothing is mailed. |

Hold your "create account" button until this answer arrives, rather than assuming a default and correcting later. If the call fails, say the feature is unavailable instead of guessing.

## Sign-up when a proved address is required

Three calls against the registration server (`serviceInfo.register`), in order.

### 1. Request a code

```http
POST {serviceInfo.register}email-challenge
Content-Type: application/json

{ "email": "alice@example.com", "language": "en" }
```

```json
{ "sent": true }
```

The core mails an 8-character code, shown to the holder as `XXXX-XXXX`. It is single-use and short-lived (10 minutes by default). Requesting a new code invalidates the previous one for that address.

What can come back instead:

| Status | Error | Meaning |
|---|---|---|
| `403` | `forbidden`, `data.emailVerificationRequired: false` | This platform does not gate sign-up. You should not have called this. |
| `409` | `item-already-exists`, `data.email` | An account already holds the address. Offer sign-in or password recovery. |
| `429` | `too-many-attempts`, `data.reason`, `data.retryAfterSeconds` | A per-address limit was hit. `reason` is `cooldown` (seconds), `daily-limit` or `failure-budget` (come back later). A `Retry-After` header carries the same delay. |
| `500` | `unexpected-error` | Delivery failed. The challenge is released, so the holder can retry at once. |

### 2. Exchange the code for a proof

```http
POST {serviceInfo.register}email-challenge/verify
Content-Type: application/json

{ "email": "alice@example.com", "code": "K7M4-P9RX" }
```

```json
{ "emailProof": "chtplghfp0000hqjx814u6393" }
```

The separator and the case do not matter, so you can send what the holder typed. A wrong, unknown or expired code all answer `401 invalid-access-token` with the same message, and `data.attemptsRemaining` tells you how many tries the pending code has left. Show that number: "that code is not valid, 4 attempts left" is the difference between a holder who retries and one who gives up. When `attemptsRemaining` is `0`, ask them to request a new code.

Once the attempts are spent the code is discarded and the endpoint answers `429 too-many-attempts` with `data.reason: "exhausted"`.

### 3. Create the account with the proof

```http
POST {serviceInfo.register}users
Content-Type: application/json

{
  "appId": "my-app-id",
  "username": "alice",
  "password": "...",
  "email": "alice@example.com",
  "emailProof": "chtplghfp0000hqjx814u6393"
}
```

The proof is bound to that address and expires (30 minutes by default), so treat it as part of the same sitting rather than something to store. Registration without it answers `403 forbidden` with `data.emailVerificationRequired: true`; a missing or empty `email` answers `400 invalid-parameters-format` with the same data field.

The founding address of an account created this way is recorded as proved, with `verificationMethod: email-code`.

Two things worth knowing: the code is minted platform-wide, so in a cluster it verifies on any core; and the rate limits above are keyed on the address, not on the caller, because these endpoints are public.

## Verifying addresses on an existing account

Addresses are managed through the account method, and each operation is a list:

```http
PUT /:username/account

{ "emails": { "add": ["alice.work@example.com"] } }
```

`add` reserves the address across the platform, records it as `pending`, and mails a verification link to it. The other operations are `remove`, `setPrimary` and `resend`, applied in that order:

- `remove` refuses the primary address;
- `setPrimary` only accepts an address that is already on the account **and** `verified`, so a newly added address cannot become primary until its link has been used;
- `resend` mails a fresh link and kills the previous one, subject to a per-address cooldown (5 minutes by default).

Adding an address another account already holds answers `409 item-already-exists`. The refusals above answer `400 invalid-operation`, with `data.email` and, for the cooldown, `data.retryAfterSeconds`.

### The verification page

The mailed link points at the page the operator configured in `auth.emailVerificationPageURL`, which is a page of **your** application. It arrives with two query parameters:

```
https://your-app.example/verify-email?verifyToken=<token>&username=<username>
```

The username is there because the call is user-scoped and the address cannot be resolved to an account from the page. Your page then calls:

```http
POST /:username/account/verify-email
Content-Type: application/json

{ "token": "<token>", "appId": "my-app-id" }
```

```json
{ "email": "alice.work@example.com" }
```

Notes for that page:

- **No access token.** The mailed token is the credential, so the holder does not need to be signed in. The call does require [trusted app verification](/reference/#basics-trusted-apps-verification), so send your `appId` and let the browser send its `Origin`.
- **One answer for every failure.** Unknown, expired, already used and belonging-to-another-account all return `401 invalid-access-token` with the same message. Do not try to distinguish them for the holder; offer "request a new link" instead.
- **Drop the token from the address bar** once you have read it, with a `history.replaceState`. Otherwise a spent token follows the holder into their history, their next page, and any `Referer` header your page sends.
- If the operator's page URL already carries its own query, the core appends with `&`, so parse the parameters rather than assuming a position.

## Reading the status back

`GET /:username/account` returns the addresses alongside the legacy singular `email`:

```json
{
  "account": {
    "username": "alice",
    "email": "alice@example.com",
    "emails": [
      {
        "value": "alice@example.com",
        "primary": true,
        "status": "verified",
        "verifiedAt": 1735682400,
        "verificationMethod": "email-code"
      },
      {
        "value": "alice.work@example.com",
        "primary": false,
        "status": "pending",
        "verifiedAt": null,
        "verificationMethod": null
      }
    ]
  }
}
```

**`status: "verified"` alone does not mean the address was proved.** The founding address of an account created without the sign-up gate is recorded as `verified` with `verificationMethod: "registration"`: asserted by whoever typed it, never demonstrated. Read `verificationMethod` whenever ownership has to be trusted, for example before treating the address as an identity:

| Value | Proved? | How it got there |
|---|---|---|
| `email-link` | yes | the holder opened a one-time link mailed to the address |
| `email-code` | yes | the holder pasted a code mailed to the address while creating the account |
| `operator` | yes | the platform operator vouched for it |
| `registration` | no | the founding address, asserted at sign-up |
| `legacy` | no | set through the singular `email` field |
| `null` | no | data predating this field |

Accounts that never used the feature report their single primary address as one entry, so the array is always safe to read.

An account holds at most `account.maxEmails` addresses (an operator setting, with a hard ceiling of 20), and exactly one is primary. The singular `email` field always mirrors the primary one.

## Where to look next

- [Email configuration](/customer-resources/emails-setup/#email-verification): the operator view, including what the mails contain and how to change them.
- [API reference](/reference/#methods-account-account-verifyEmail): verify email address, and the `emails` operations of update account information.
- [System API](/reference-system/#request-an-email-challenge): the two registration endpoints.
- [app-web-user-account](/apps/app-web-user-account/): a reference application implementing all of the above, including the sign-up step and the verification page.

This surface is **beta**: it may still change before it is declared stable.
