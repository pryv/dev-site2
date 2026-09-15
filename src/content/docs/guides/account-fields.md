---
title: 'Requesting account fields from an app'
description: How an application asks for read access to a Pryv.io account field such as the email or the language, which prefix each field carries, and how to read the value back.
---

## Introduction

An account holder's own details, their email address, their language, how much storage they use, are not ordinary events. They are **account fields**, exposed as system streams, and an application can be granted access to them through the normal authorization flow, with the holder's explicit consent at the usual consent step.

This guide is for application developers. It covers which fields can be requested, how to spell their stream ids, which permission level to ask for, and how to read the value back. For the operator-side view, how the field schema is configured, see [System streams](/customer-resources/system-streams/).

The most common case: an application that wants the holder's email address without asking them to type it a second time.

## The two prefixes

Account fields carry one of two prefixes, and which one a field takes is the single most common source of confusion.

| Prefix | Meaning | Examples |
|---|---|---|
| `:_system:` | built into Pryv.io | `:_system:language`, `:_system:storageUsed` |
| `:system:` | defined by the platform's configuration | `:system:email` |

**The email is a platform-defined field, so it is `:system:email`, not `:_system:email`.** It is not built in because some platforms deliberately omit an email address entirely, for account anonymity. The same applies to any additional field an operator declares, such as an insurance number.

There is no `:_system:email`.

What you get back when you request it depends on the version. Up to and including 2.0.0-rc.17, the request is refused with a bare `403 forbidden` carrying no message, which is easy to mistake for a deliberate policy refusal rather than a wrong id. A later release replaces that with a `400` naming the id and restating the prefix rule. If you are on a current deployment and see an unexplained `403` on an account stream, suspect the prefix first.

If you are unsure what a given platform declares, ask its operator: the account-field schema is deployment configuration, and every core in a platform shares it.

## What can be requested

A field is requestable only if it is visible. Built-in bookkeeping fields (`appId`, `invitationToken`, `referer`) are marked not-shown and are refused with a `400`; they are not part of an application's surface.

Practically, on a default configuration:

| Field | Stream id |
|---|---|
| Email | `:system:email` |
| Language | `:_system:language` |
| Storage used | `:_system:storageUsed` |

## Asking for it

Include the permission in `requestedPermissions` exactly as you would for any stream. A `defaultName` is required:

```json
{
  "requestingAppId": "my-app",
  "requestedPermissions": [
    { "streamId": ":system:email", "level": "read", "defaultName": "Email" }
  ]
}
```

The consent screen resolves the field's configured label, so the holder sees `Read "Email"` rather than a raw stream id.

**Ask for `read`.** Levels above `contribute` are refused on account fields. Write access to the holder's address is rarely what an application wants: an address changed that way goes through no verification at all, so it is worth less than the one already on the account.

A caution on the plain name: requesting `email` with no prefix is currently accepted, but it is a *different*, ordinary stream that merely looks right on the consent screen. It will be empty, and it will stay empty. Always include the prefix.

## Reading the value

Account fields are read through the events API, like any other stream:

```
GET /events?streams=[":system:email"]
```

The response carries a single event for that field, whose `content` is the current value.

Two things to know about what you get:

- Wildcard queries never expand into the account namespace. You must name the stream explicitly.
- An application granted read on the email sees the **current primary address only**. An account can hold further addresses, including ones awaiting verification, and none of them is reachable through this permission, even by naming their stream.

A caution worth stating plainly: being the primary address does not by itself mean the holder has proved control of that inbox. An address set at registration is asserted, not inbox-verified. If your use case depends on the address having been demonstrably confirmed, treat that as a separate question to put to the operator rather than an assumption you can make from reading the field.

## Why not a copy of your own

An application can always ask the holder to type their address again and store it as an ordinary event. That works, and it is what applications did before this was documented, but it creates a second copy of the same personal data with its own lifecycle: it does not follow a change of account email, and clearing it is a separate obligation from deleting the account.

Requesting the field keeps one authoritative copy, which is the better answer for data minimisation and the one to prefer where the platform declares the field.

## Related

- [System streams](/customer-resources/system-streams/), the operator-side configuration of the field schema.
- [Consent implementation](/guides/consent/), for the consent flow these permissions travel through.
- [Application guidelines](/guides/app-guidelines/).
