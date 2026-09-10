---
title: 'Third-party sign-in (SSO)'
description: How an operator lets account holders sign in to Pryv.io through an external OpenID Connect identity provider (e.g. Google), and how the minted session is handed to the auth app without ever putting a token in a URL.
sidebar:
  badge:
    text: Beta
    variant: caution
---

:::caution[Beta]
Third-party sign-in is a beta feature. It is off by default and the config /
behaviour may still change. Enable it deliberately, on a single-core / dnsLess
deployment.
:::

This page is for **platform operators** deciding whether to enable third-party
sign-in, and for **auth-app developers** integrating the sign-in buttons and the
landing page. With this feature the core acts as an OpenID Connect **client**
(relying party): an account holder signs in through an external identity
provider you configure (for example Google), instead of typing a Pryv.io
password.

It is distinct from the [OAuth2 layer](/customer-resources/auth-oauth2/), where
the core is the OAuth2 **server** authorizing third-party apps. Here the core is
the OAuth2/OIDC **client** toward the external provider, and the outcome is a
normal Pryv.io personal session for the user.

## Prerequisites

- **Single-core / dnsLess only** in this version. `sso.enabled: true` alongside
  the embedded DNS (`dns.active: true`) is refused at boot; cross-core session
  hand-off is deferred.
- **Shared secrets must be enabled** (`sharedSecrets.enabled: true`, the
  default). The sign-in callback hands the minted session token to the auth app
  only through a one-time shared secret, never in a URL; the core refuses to
  boot `sso.enabled` without it.
- An **auth app** that hosts the sign-in buttons and the landing page (the
  reference [app-web-user-account](https://github.com/pryv/app-web-user-account)
  implements both).
- A **registered OIDC client** at each provider, whose redirect URI is
  `<callbackBaseURL>/auth/sso/<provider>/callback` (registered verbatim).

## Operator configuration

Add a top-level `sso` block. It is inert until `enabled: true` with at least one
provider.

```yaml
sso:
  enabled: false                 # master switch (default false)
  landingPageURL: ''             # the auth-app page that receives the hand-off
                                 # (REQUIRED when enabled); include the service
                                 # info URL, e.g.
                                 # https://sw.example.com/sso-signin?pryvServiceInfoUrl=https%3A%2F%2Freg.example.com%2Fservice%2Finfo
  callbackBaseURL: ''            # optional; defaults to the core API origin.
                                 # <base>/auth/sso/<provider>/callback must be
                                 # registered at each IdP
  providers:                     # operator allow-list, keyed by provider id
    google:
      issuer: 'https://accounts.google.com'
      clientId: '<your-client-id>'
      clientSecret: '<your-client-secret>'
      label: 'Google'            # shown on the sign-in button
```

Validate a config with `node bin/check-config.js` before deploying: it refuses
`sso.enabled` with `dns.active`, a non-https `callbackBaseURL`, a providers list
that is not a map, a bad provider id, a missing `issuer` / `clientId` /
`clientSecret`, and `sso.enabled` without `sharedSecrets.enabled`.

:::note[Name collision]
The `sso:` block is unrelated to the legacy `auth.ssoCookie*` keys, which
configure the trusted-app session cookie. They share the letters "sso" and
nothing else.
:::

## The flow

1. The auth app fetches `GET /auth/sso/providers` (public: id + label only, no
   secrets) and renders a "Sign in with <label>" button per provider.
2. The button sends the browser to `GET /auth/sso/<provider>/start`. The core
   sets a signed state cookie and 302s to the provider's authorization endpoint.
3. The user authenticates at the provider; the provider 302s back to
   `/auth/sso/<provider>/callback` with a code.
4. The core exchanges the code, validates the id_token, and resolves the account
   (see [Account linking](#account-linking)). It then mints a normal personal
   session and 302s to `sso.landingPageURL` with the result on the URL
   **fragment** (never the query, so nothing SSO-related reaches the landing
   host's access log or the Referer header):
   - `#ssoStatus=login&ssoUser=<username>&ssoKey=<one-time-key>` on success;
   - `#ssoStatus=mfa&ssoUser=<username>&ssoMfaToken=<token>&ssoMfaMethod=<m>`
     when the account has MFA active;
   - `#ssoError=<code>` on refusal (`no-account`, `email-not-verified`,
     `sso-failed`).
5. The landing page reads the fragment, clears it, and:
   - on `login`, POSTs the key to `/<username>/shared-secrets/retrieve` (no
     credentials needed) and receives the session token once; the token was
     never in a URL;
   - on `mfa`, shows the second-factor entry and completes `/<username>/mfa/verify`
     to obtain the token (the same continuation as a password login with MFA);
   - on an error, shows a message for the coarse code.

## Account linking

The first successful sign-in through a provider links the provider's stable
subject to a Pryv.io account, and only when the account has **proved ownership**
of the provider's verified email; later sign-ins ride that link (the subject is
authoritative, so a later email change at the provider does not re-route the
login).

The proof requirement is a takeover gate: an account whose email address was
never inbox-proved cannot be claimed by an external identity that merely asserts
the same address. An account holder proves an address by clicking the mailed
verification link (Emails setup / verification), which upgrades the address to
proved. If the address is not proved, sign-in is refused with
`email-not-verified`, and the auth app can prompt the user to verify it first.
An address that resolves to no account is refused with `no-account` (this
version does not auto-create accounts).

## Managing links

There is no user-facing unlink surface in the beta. Operators manage links with
`bin/sso-link.js`:

```
node bin/sso-link.js list <username>                       # a user's bindings
node bin/sso-link.js show <provider> <subject>             # who a binding maps to
node bin/sso-link.js unlink <username> <provider> <subject> --yes
```

`unlink` is owner-guarded (it never removes another account's binding). Under
`platform.piiMode: hashed`, stored subjects are one-way tokens, so `list` cannot
show the cleartext subject; `unlink` still works when you supply the original
cleartext subject from the provider or the support context.

## Security notes

- **No token in a URL.** The long-lived session token is delivered only through
  the one-time shared secret; a mint or hand-off failure yields the uniform
  `sso-failed` error, never a token in the fragment. The MFA branch hands off
  only the short-lived, second-factor-gated `mfaToken`.
- **id_token authenticity** relies on TLS to the provider plus your client
  secret (the openid-client default under OIDC Core section 3.1.3.7): the
  id_token comes directly from the token endpoint over an authenticated channel.
  A per-validation JWS signature check is available as opt-in defense in depth
  and is not required for the standard flow.
- **Fail closed.** Every refusal surfaces as one coarse code; the detail stays
  in the server log and audit trail, and no identifiers are logged.
