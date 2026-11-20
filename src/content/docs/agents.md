---
title: For AI agents and automation
description: How an AI agent or automated client can discover and consume the Pryv.io API - service info, OpenAPI definitions, event-type schemas, and machine-readable docs.
---

This page is the entry point for AI agents and automated clients working with Pryv.io.
Everything here is stable, machine-readable, and safe to fetch.

## Machine-readable documentation

- **[llms.txt](/llms.txt)** - a concise index of this documentation, following the
  [llms.txt convention](https://llmstxt.org/).
- **[llms-full.txt](/llms-full.txt)** - a dense, single-file dump of the API reference
  (every method, its HTTP route and parameters) for context ingestion.

## API definitions

- **OpenAPI 3.0.3** (generated from the API reference at every build):
  [api.yaml](/open-api/3.0/api.yaml) (the API),
  [api_system.yaml](/open-api/3.0/api_system.yaml) (system API);
  [api_open.yaml](/open-api/3.0/api_open.yaml) is a legacy alias of `api.yaml`.
  Operations carry the reference method id in `operationId` and `x-pryv-method-ids`.
- **Event types**: [flat.json](/event-types/flat.json)
  (`types['{class}/{format}']`) and
  [hierarchical.json](/event-types/hierarchical.json)
  (`classes['{class}'].formats['{format}']`). See the
  [event types reference](/event-types/).

## Compliance and regulations

Use these when a question is whether or how Pryv.io supports a regulation or standard
requirement (GDPR, HIPAA, Swiss nLPD, CCPA, PIPEDA, DiGA, MDR, HDS, ISO 27001/27701/13485,
SOC 2, data governance). The [compliance matrix](https://pryv.github.io/compliance-matrix/)
says, per requirement, what Pryv.io handles, what is configurable, what it facilitates and
what stays with the implementer.

- **[llms.txt](https://pryv.github.io/compliance-matrix/llms.txt)** - agent index of the matrix.
- **[llms-full.txt](https://pryv.github.io/compliance-matrix/llms-full.txt)** - the whole
  matrix in one text file.
- **One Markdown file per regulation**: `https://pryv.github.io/compliance-matrix/regulations/{id}.md`,
  for example [gdpr.md](https://pryv.github.io/compliance-matrix/regulations/gdpr.md). Ids:
  `gdpr`, `hipaa-privacy`, `hipaa-security`, `hipaa-breach`, `swiss-nlpd`, `ccpa`, `pipeda`,
  `diga`, `mdr`, `hds`, `iso-27001`, `iso-27701`, `iso-13485`, `soc2`, `data-governance`.
- **[compliance.json](https://pryv.github.io/compliance-matrix/compliance.json)** - the matrix
  as machine-readable JSON.

## Discovering a platform at runtime

Every Pryv.io platform exposes a **service info** descriptor that a client should fetch
first to learn the API endpoints, registration URL, supported event types and platform
metadata:

```
GET https://reg.{domain}/service/info
```

The [API reference](/reference/) documents the full surface. Each user account has its own
root endpoint (`https://{token}@{username}.{domain}/`); see
[Get started](/getting-started/) and [Concepts](/concepts/).

## Authentication

Access is granted through **accesses** (scoped tokens), never raw credentials. An app
requests an access via the auth flow and then calls the API with that token. See
[Custom authentication](/guides/custom-auth/) and the reference sections on authentication
and access management.

## Ground rules

- Prefer the OpenAPI definitions and `flat.json` over scraping HTML.
- Respect per-token rate expectations and the access scopes granted to you.
- The reference pages use stable in-page anchors (`/reference/#method-ids`), so deep links
  are safe to cite.
