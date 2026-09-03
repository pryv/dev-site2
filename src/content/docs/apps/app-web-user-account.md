---
title: 'app-web-user-account'
description: Overview of app-web-user-account, the themeable reference web app for Pryv.io authentication and self-service account management, with links to the repository.
---

`app-web-user-account` is a **reference web application** for Pryv.io end users. It
provides the authentication flows (sign-in, registration, password reset) and a
**self-service account management** interface on top of the [API](/reference/): profile,
security and MFA, connected apps and accesses, data rights, and cross-account approval.

It is built with **React, TypeScript, Vite and Tailwind**, is **themeable**, and is meant
to be **self-hosted** by platform operators as the customer-facing account app (the modern
successor to the older auth web app).

## When to use it

Use it as the ready-made auth and account-management front end for your platform, or as a
starting point you fork and rebrand. If you only need programmatic access, use
[lib-js](/libraries/lib-js/) or the [API](/reference/) directly.

## Features

- Sign-in, registration and password reset flows.
- Profile and preferences management.
- Security: password, multi-factor authentication.
- Connected apps and access (token) management, with revocation.
- Data rights (export / deletion) entry points.
- Cross-account approval flows.

## Documentation and source

Setup, configuration, theming and deployment are documented in the repository:

- **Repository**: [github.com/pryv/app-web-user-account](https://github.com/pryv/app-web-user-account)

For operators wiring it into a platform, see the [platform setup guide](/customer-resources/pryv.io-setup/).
