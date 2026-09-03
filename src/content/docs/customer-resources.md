---
title: 'Setup'
description: Documents, files and guides for installing and operating Open Pryv.io v2, the single-binary API server, including upgrading from v1 deployments.
---


In this space you will find documents, files and guides for the installation and operation of **Open Pryv.io**.

Since v2, Open Pryv.io is distributed as a single repository and Docker image — [pryv/open-pryv.io](https://github.com/pryv/open-pryv.io) — under the [BSD-3-Clause](https://opensource.org/license/bsd-3-clause) license. The API server, registration, MFA, high-frequency series and preview services all run from the same binary, driven by [`bin/master.js`](https://github.com/pryv/open-pryv.io/blob/master/bin/master.js).

Related components:
- [open-pryv.io](https://github.com/pryv/open-pryv.io): Main API server (core + register + mail + MFA + HFS + previews)
- [dev-migrate-v1-v2](https://github.com/pryv/dev-migrate-v1-v2): Toolkit to migrate user data from Open Pryv.io 1.x to v2

## Upgrading from v1

If you already run Open Pryv.io 1.x and want to move your users to v2:

1. Install a fresh v2 core following the [platform setup guide](/customer-resources/pryv.io-setup/).
2. Use [`dev-migrate-v1-v2`](https://github.com/pryv/dev-migrate-v1-v2) to export your v1 MongoDB into a v2-compatible backup directory.
3. Import that backup into the v2 install with `node bin/backup.js --restore /path/to/backup` — see the [backup guide](/customer-resources/backup/).

See the toolkit's README for the current source/target support matrix.

The following repositories powered the v1 multi-container topology and are kept online as historical references only — v2 deployments should not use them:

- [service-config-leader](https://github.com/pryv/service-config-leader) / [service-config-follower](https://github.com/pryv/service-config-follower): centralized configuration management (replaced in v2 by `override-config.yml` merged onto `config/default-config.yml` at startup).
- [service-ssl-certificate](https://github.com/pryv/service-ssl-certificate): Let's Encrypt automation (replaced in v2 by the built-in `letsEncrypt.*` config block — see [SSL certificate](/customer-resources/ssl-certificate/)).

If you are migrating a v1 register service, the historical [register migration guide](/customer-resources/register-migration/) is still online — but in v2 the register role is built into the core binary, so use [core migration](/customer-resources/core-migration/) instead.


## Documents

- Functional Requirement Specification: [pryv.github.io/functional-specifications](/functional-specifications/)

  Functional specifications for the Pryv.io middleware system: the capabilities and functions that the system must be capable of performing.

- Tests Results: [tests](/tests)

  Result of tests suite on `open-pryv.io` for the latest Open Pryv.io version.


## Files

- Pryv.io configuration files: [HTML](https://pryv.github.io/config-template-pryv.io/)

  Configuration files to install Open Pryv.io.


## Guides

- Pryv.io platform setup guide: [HTML](/customer-resources/pryv.io-setup/)

- Infrastructure procurement (Previously "Deployment design guide"): [HTML](/customer-resources/infrastructure-procurement/)

  This document describes how to deploy a Pryv.io platform as well as essential information to help you decide on your infrastructure and sizing needs.
  You will also find information about how to operate your Pryv.io platform.

- Generate SSL certificate: [HTML](/customer-resources/ssl-certificate/)

  This document describes how to obtain a wildcard SSL certificate for your running Pryv.io platform using Let's Encrypt.

- Installation validation: [HTML](/customer-resources/platform-validation/)

  This document describes the steps to validate that a Pryv.io platform is up and running after deployment.

- System monitoring: [HTML](/customer-resources/healthchecks/)

  This document describes the steps to perform regular healthchecks on a running Pryv.io platform.

- System streams: [HTML](/customer-resources/system-streams/)

  This document describes how to setup and configure your platform's system streams.

- DNS configuration: [HTML](/customer-resources/dns-config/)

  This document describes how to add entries in your Pryv.io associated domain DNS zone.

- Emails configuration: [HTML](/customer-resources/emails-setup/)

  This document describes how to configure the sending of Pryv.io emails for welcoming new users or resetting lost passwords.

- Audit configuration: [HTML](/customer-resources/audit-setup/)

  This document describes how to setup audit capabilities for your Pryv.io platform.

- Core migration: [HTML](/customer-resources/core-migration/)

  This document describes how to migrate a Pryv.io core service to a different machine.

- Single-node to Cluster upgrade: [HTML](/customer-resources/single-node-to-cluster/)

  This document describes how to upgrade a Pryv.io single-node installation to a cluster one.

- User deletion

  In v2 (`open-pryv.io`), user deletion is an in-process API call: `DELETE /users/:username` (method id `auth.delete`). It removes the user's events, streams, attachments, high-frequency series and audit log in one operation. Authenticate either with the user's own personal token or with the platform `adminAccessKey`. See the [system API reference](/reference-system/#delete-user). The v1 `pryv-cli delete-user` Docker tool is not used in v2 — there is no separate CLI container.

- How to backup: [HTML](/customer-resources/backup/)

  This document describes how to perform a backup of your Pryv.io platform and how to restore it.

- MFA configuration: [HTML](/customer-resources/mfa/)

  This document describes how to enable and configure multi-factor authentication on top of the Pryv.io login.

- OAuth2 app authorization: [HTML](/customer-resources/auth-oauth2/)

  This document describes the OAuth2 authorization-code flow (RFC 6749 + PKCE), when to choose it over the Pryv-native access-request polling flow, and how multi-core clients follow the `apiEndpoint` token-response extension.

- Observability: [HTML](/customer-resources/observability/)

  This document describes the optional telemetry layer — what it emits and what it cannot emit, how to point it at any OTLP backend (including a collector you host yourself), and how to enable, tune the reporting interval, rotate credentials and disable it.


## Contact and support

You can get in touch with Pryv's support at [Open Pryv - Issues and question](https://github.com/pryv/open-pryv.io/issues)
