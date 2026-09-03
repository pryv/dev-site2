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

- **OpenAPI 3.0**: [api.yaml](/open-api/3.0/api.yaml) (hosted platforms),
  [api_open.yaml](/open-api/3.0/api_open.yaml) (open-source),
  [api_system.yaml](/open-api/3.0/api_system.yaml),
  [api_admin.yaml](/open-api/3.0/api_admin.yaml).
- **Event types**: [flat.json](/event-types/flat.json)
  (`types['{class}/{format}']`) and
  [hierarchical.json](/event-types/hierarchical.json)
  (`classes['{class}'].formats['{format}']`). See the
  [event types reference](/event-types/).

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
