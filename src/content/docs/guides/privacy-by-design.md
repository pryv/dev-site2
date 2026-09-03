---
title: 'Privacy by design and by default with Pryv.io'
description: "How Pryv.io supports privacy by design and by default: its architecture, the platform defaults that protect personal data, and the developer's role."
---


In this guide we address developers building data-collecting applications who want to understand how Pryv.io supports privacy by design and privacy by default.
It describes Pryv.io's architectural choices, the platform defaults that protect personal data out of the box, and what remains in the developer's hands.

## Introduction

The new [FADP](https://www.fedlex.admin.ch/eli/cc/2022/491/en) and [GDPR](https://gdpr.eu) require all organizations to be able to answer, on demand, a list of data-subject questions: *send me a copy of all my data*, *tell me who has accessed my data*, *prove that you have my consent*, *let me modify who can access my data*, *delete my personal data*.

These obligations land on developers and IT engineering, not just on legal teams. The platform you build on either makes these answers easy to produce — or it doesn't.

Pryv.io was designed from the start so that **the platform answers most of these questions for you, by construction**. This guide walks through what that means in practice: the architecture that makes privacy structural rather than an afterthought, the data model that gives you granular consent for free, and the platform defaults that protect personal data the moment your app goes live.

## Why a developer should care

In the past decades, organizations moved from treating personal data as a **data asset** to recognizing it as a **data debt**. Vast amounts of personal data were collected; regulations and user expectations caught up; established data-governance practices became outdated.

Developers building today inherit that debt unless the substrate they use clears it for them. Designing for privacy from the beginning — privacy by design — is much cheaper than retrofitting it later. And shipping privacy-protective defaults — privacy by default — raises the level of trust with your users, which translates into better sign-up rates, better retention, and more willingness to share data.

## Glossary

- **Data Subject**: the individual the personal data relates to.
- **Data Controller**: the organization that determines the purposes and means of processing personal data.
- **Data Processor**: the organization that processes personal data on behalf of the Data Controller.
- **Processing register** (Art.30): a record of general information on the type of personal data you process and to what end.
- **Subcontractor agreement** (Art.28): defines the conditions under which a Data Processor undertakes to carry out personal data processing on behalf of a Data Controller.

## Privacy by design in Pryv.io

Privacy by design means proactively considering privacy throughout the data lifecycle, starting from the very first design phase. Article 25(1) of the GDPR requires controllers to integrate data-protection principles at the time the means for processing are determined — not as a later add-on.

### The standard pattern and its limits

Most platforms put access control next to the data, like this:

```
Processes ──direct access──► Personal Data
              │
              ▼
         Audit / Logs (after-the-fact, manual)
```

The consequences:

- Processes have **direct** access to personal data.
- Per-resource access is **not tracked** — audit is procedural and retroactive.
- The process registry is maintained **manually**; it drifts; when an auditor asks "show me your Art.30 register" you run a spreadsheet exercise.

### Pryv.io's architecture

Pryv.io puts Access Control on its own layer, between every process and any personal data:

```
       Data Governance
              │
              ▼
Processes ─►Access Control ─►Personal Data
              │
              ▼
   Audit / Logs per-Data-Subject (invariant, automatic)
```

- Access Control is a **separate enforcement layer**. No process talks directly to storage; every request resolves through an Access object (a token granting specific permissions on specific streams).
- Governance is applied **per-process AND per-data-subject** — every access on every subject's account carries its own permission scope, its own audit trail, and its own version chain.
- The **process registry is self-documented**: `GET /accesses` plus the audit log together IS your Art.30 records-of-processing register, derivable on demand. No spreadsheet exercise.

This isn't a recommended deployment pattern. It's what the platform ships.

### Data model: subject and context segregation

The standard relational model — one schema organized for processing purposes (customer table, account table, service-record table) — has three privacy problems:

- It is not related to the data subject's understanding ("which rows in the customer table are mine?" doesn't have a clean answer).
- Access enforcement is difficult to track per-record.
- Consent text becomes a wall-of-text privacy policy that very few users read.

Pryv.io segregates data by **data subject AND context** instead:

- Every event belongs to one subject's account.
- Events are organized in **streams** representing context — `health/vitals/temperature`, `health/sleep`, `diary/notes`, `nutrition/meals`, etc.
- Each access permission targets a specific stream (or subtree): `{ streamId: "health", level: "read" }` grants read access to everything under `health/*` and nothing else.

The subject sees explicit grants when accepting an application:

```
App "Personal Log Book" requests:
 - Edit "Nutrition"
 - Edit "Diary"
 - Read "Advices"

[Accept]  [Refuse]
```

instead of a wall of legalese.

This segregation is the structural substrate for:

- **Granular consent** ([Art.7](https://gdpr.eu/article-7-how-to-get-consent-to-collect-personal-data/)) — each requested permission is separately presentable and acceptable.
- **Data minimisation** (Art.5(1)(c)) — the application reads exactly what its grant covers, nothing else.
- **Portability** ([Art.20](https://gdpr.eu/article-20-right-to-data-portability/)) — per-stream-subtree export is a natural operation.
- **Erasure** ([Art.17](https://gdpr.eu/article-17-right-to-be-forgotten/)) — per-stream-subtree deletion is too.

And your data stays usable by machines — events carry a structured `type: class/format` JSON Schema, so analytics and ML pipelines consume them like any tabular store.

For a deeper walkthrough of the data model, see the [Data modelling](/guides/data-modelling/) guide.

## Privacy by default in Pryv.io

Privacy by default means **automatically protecting personal data without any action from the data subject**. Article 25(2) of the GDPR puts it this way: by default, only personal data necessary for each specific purpose are processed.

### The opt-in pattern

Most cookie banners ship the privacy anti-pattern:

> *"This site uses cookies to provide you with an optimal browsing experience. By continuing to visit this site, you agree to the use of these cookies."*

Privacy is opt-out: the user must navigate to preferences to **deactivate** processing they didn't actively choose.

Privacy by default flips this:

> *"By default, non-necessary cookies are deactivated. You can help us improving our website by activating analytics cookies."*
>
> [ACTIVATE] [CONTINUE]

Privacy is opt-in: the user must explicitly **activate** the processing categories they want to enable.

The reference auth flow shipped with Pryv.io — [app-web-user-account](https://github.com/pryv/app-web-user-account) (formerly app-web-auth3) — implements this pattern by default. The auth screen surfaces the requested permissions explicitly, per stream and per level (read / write / contribute / manage); Accept and Refuse buttons are visually balanced; the granted permissions are stored on the access and remain revocable at any time via `DELETE /accesses/:id`.

The auth UI primitive doesn't support the anti-pattern — you can't accidentally ship a "by continuing you agree" flow even if you wanted to.

See the [Consent implementation](/guides/consent/) guide for the detailed walkthrough.

### Twelve platform defaults

When an auditor asks "show me what's privacy-protective by default", point at this catalogue:

- **Default-deny on permissions.** Every access starts with empty `permissions: []`. You explicitly grant scope; nothing is read by default.
- **Audit-on by default.** The audit primitive is invariant — no config flag turns it off. Every API call against every subject's account is captured at write time.
- **TLS enforced.** Let's Encrypt integration makes HTTPS the default. HTTP-only is a deliberate dev-mode opt-in.
- **Hosting region pinned per user.** Once a subject is assigned to a core, all their event data lives on that core exclusively. Residency is architectural, not configurable per event.
- **Stream-permission granularity.** Permissions are per-stream-subtree. There is no "public" tier — sensitive data can't be accidentally exposed to a world-readable surface that doesn't exist.
- **Data-minimal audit.** The audit log captures method + access reference + URL query + integrity hash. It **never** captures the request body. Audit storage is safe to retain at long horizons because it contains no event content.
- **Schema validation at ingest.** Every event is validated against the declared event type's JSON Schema (`ajv-draft-04`) on `create` AND `update`. Out-of-shape or out-of-range payloads are rejected with HTTP 400.
- **Zero mandatory subprocessors.** Default deployment talks to zero third-party services beyond your chosen cloud provider. SMTP, SMS, observability, Let's Encrypt — every integration is opt-in.
- **Credentials never leak via logs.** Every log call passes through a redaction layer that strips `auth=...` tokens and `password` / `passwordHash` fields. Credentials don't leak to external aggregators.
- **Cross-account sharing requires explicit subject consent.** Pryv.io's [CMC primitive](/guides/cross-account-messaging/) requires the subject to write a `consent/accept-cmc` event before any cross-account data flow begins.
- **Operator secrets encrypted at rest.** Let's Encrypt account keys, observability license keys, SMTP credentials are AES-256-GCM encrypted with HKDF-derived keys.
- **Withdrawal API exists by default.** `DELETE /accesses/:id` is always available. A subject holding their personal token can revoke any access without third-party participation.

## What stays in the developer's hands

The defaults above are structural — Pryv.io enforces them. But Art.25(2) also has axes the platform can't decide for you:

- Are app tokens minted with the **smallest possible scope**? Pryv.io lets you grant any scope; choosing the smallest is your editorial discipline.
- Is your subject's **notice-of-collection presented by default**? The consent text plus the access's `clientData` conventions (see the [Consent implementation](/guides/consent/) guide) give you the durable, audit-traceable record; what the notice **says** is yours to write.
- Is **data retention set to the shortest necessary period**? Pryv.io doesn't enforce retention; your operational pruning pipeline does.
- Is your custom auth UI using the **opt-in pattern** rather than the "by continuing you agree" anti-pattern? If you rebrand `app-web-user-account`, the default pattern is opt-in; custom UI is your responsibility to align.

## Privacy-enhancing technologies

Cryptography-based PETs that you can layer on top of Pryv.io's substrate:

- **Pseudonymisation** — personal-data fields replaced by artificial identifiers before analysis or sharing. The access + stream model already provides structural pseudonymisation; a randomised-alias primitive is on the roadmap.
- **Proxy re-encryption** — data is encrypted per segment with the data subject's public keys; the backend re-crypts for accredited recipients on demand. Defends against full-dataset breach because the attacker needs the secret keys of accredited recipients. A working proof of concept is available at [github.com/perki/test-proxy-re-encrypt](https://github.com/perki/test-proxy-re-encrypt).
- **Multiparty computation** (federated learning, mining data without revealing sensitive information) — multiple parties compute a function over their private inputs without revealing them.
- **Homomorphic encryption** — computations performed on encrypted data without decrypting it.
- **Differential privacy** — calibrated noise added to statistical releases so that individual data points cannot be re-identified.

Pryv.io's architecture doesn't preclude any of these — they sit on top of the platform substrate. The choice of which PETs to add is yours.

## References

- [GDPR full text](https://gdpr.eu) — official EU regulation.
- [Article 25 — Data protection by design and by default](https://gdpr.eu/article-25-data-protection-by-design).
- [Swiss Federal Act on Data Protection (FADP)](https://www.fedlex.admin.ch/eli/cc/2022/491/en).
- [Consent implementation with Pryv.io](/guides/consent/) — companion guide.
- [Audit logs](/guides/audit-logs/) — companion guide.
- [Cross-account messaging (CMC)](/guides/cross-account-messaging/) — CMC consent flow.
- [Data modelling](/guides/data-modelling/) — streams + events deep dive.
- [App guidelines](/guides/app-guidelines/) — implementer-facing patterns.
- [app-web-user-account on GitHub](https://github.com/pryv/app-web-user-account) — the reference auth web app.
