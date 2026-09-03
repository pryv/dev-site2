---
title: 'Pryv.io system streams'
---


This document explains how to set up system streams.

> **Since v2 (2026)** system streams are configured in the unified config file under `custom.systemStreams.account` / `custom.systemStreams.other` (plain YAML). There is no `ACCOUNT_SYSTEM_STREAMS` / `OTHER_SYSTEM_STREAMS` JSON-encoded string, no admin-panel *Advanced API settings* tab, and no `BACKWARD_COMPATIBILITY_SYSTEM_STREAMS_PREFIX` switch — v2 uses the `:_system:` / `:system:` prefix scheme exclusively. The module implementing the runtime behaviour lives at [`components/business/src/system-streams/`](https://github.com/pryv/open-pryv.io/tree/master/components/business/src/system-streams).


## Table of contents <!-- omit in toc -->

1. [About system streams](#about-system-streams)
   1. [Unicity](#unicity)
   2. [Indexed](#indexed)
   3. [Editability](#editability)
   4. [Requiredness at registration](#requiredness-at-registration)
   5. [Format](#format)
   6. [Event type](#event-type)
   7. [Visibility](#visibility)
2. [Configuration](#configuration)
   1. [Schema](#schema)
   2. [Baked-in account streams](#baked-in-account-streams)
   3. [Adding custom account streams](#adding-custom-account-streams)
   4. [Adding custom *other* streams](#adding-custom-other-streams)
   5. [Modification caveats](#modification-caveats)
3. [Backward compatibility (historical)](#backward-compatibility-historical)


## About system streams

System streams are a predefined set of streams. They are loaded in memory by Pryv.io from the config file at startup and are not stored in the database.

The base set contains the structure for storing user account data. You can extend it in the unified config with custom streams to add unique or indexed fields.

System stream IDs are prefixed with `:_system:` (baked-in defaults) or `:system:` (operator-defined custom). In versions prior to 1.7 the prefix was `.` (dot). See [Backward compatibility](#backward-compatibility-historical) below.

The baked-in account tree in v2 is:

```
:_system:account
  ├─ :_system:language          (indexed)
  ├─ :_system:appId              (indexed, required at registration, hidden)
  ├─ :_system:invitationToken    (indexed, hidden)
  ├─ :_system:referer            (indexed, hidden)
  └─ :_system:storageUsed
       ├─ :_system:dbDocuments   (read-only)
       └─ :_system:attachedFiles (read-only)
```

Custom streams that you define for your platform are prefixed with `:system:`. The most common custom addition is `email` (shown below); it is **not** baked-in because some Pryv.io platforms intentionally omit email for account anonymity.

There are two sets of custom streams:

- **Account** custom streams are children of the `:_system:account` stream. They may carry additional properties (unicity, indexation, requiredness at registration, format, event type, visibility).
- **Other** custom streams sit at the root of the stream tree and cannot carry those per-account constraints.

### Unicity

You can define fields whose uniqueness constraint will be enforced platform-wide — typically email or insurance number. Only available for *account* streams.

### Indexed

Account properties can be marked as indexed, making them queryable through the [admin GET /users](/reference-system/#get-users) system API across all accounts. Only available for *account* streams.

### Editability

Values of system streams are stored as events in the [Events data structure](/reference/#event). You can declare whether the event is editable or read-only after account registration. Only available for *account* streams.

### Requiredness at registration

Some values can be required during the registration flow. Only available for *account* streams.

### Format

You can enforce a value format using a regular expression. Only available for *account* streams.

### Event type

You can choose the `type` (e.g. `email/string`, `phone/string`) of the events used to store the values. Only available for *account* streams.

### Visibility

You can store values at registration and index them, but keep them out of the public Pryv.io API (only exposed through the admin API). Only available for *account* streams.


## Configuration

### Schema

Each entry in `custom.systemStreams.account` or `custom.systemStreams.other` is validated against the following shape on startup:

| Field | Type | Default | Notes |
|---|---|---|---|
| `id` | string | — | required; `:system:` prefix auto-applied |
| `name` | string | — | required |
| `type` | string | — | required; matches `/^[a-z0-9-]+\/[a-z0-9-]+$/` |
| `isUnique` | boolean | `false` | account-only |
| `isIndexed` | boolean | `false` | account-only |
| `isEditable` | boolean | `true` | account-only |
| `isRequiredInValidation` | boolean | `false` | account-only |
| `regexValidation` | string | `null` | account-only |
| `isShown` | boolean | `true` | account-only |
| `default` | any | — | default value assigned on account creation |
| `children` | array | `[]` | nested streams |

Validation failures log an error and fail core startup — catch them early by running `node bin/master.js --config <your-override>.yml` once after any edit.

### Baked-in account streams

These are always present and cannot be removed via `custom.systemStreams.account`:

```yaml
# Implicit — see config/plugins/systemStreams/index.js for the authoritative list
:_system:account:
  - language       (isIndexed, default 'en')
  - appId          (isIndexed, isRequiredInValidation, isShown: false, isEditable: false)
  - invitationToken(isIndexed, isShown: false, isEditable: false)
  - referer        (isIndexed, isShown: false, isEditable: false)
  - storageUsed:
      - dbDocuments  (isEditable: false)
      - attachedFiles(isEditable: false)
```

### Adding custom account streams

Put your additions under `custom.systemStreams.account` in `override-config.yml`. The default shipped config contains the `email` stream as a reference — duplicate its shape for your own fields.

```yaml
custom:
  systemStreams:
    account:
      - id: email
        name: Email
        type: email/string
        isUnique: true
        isIndexed: true
        isShown: true
        isEditable: true
        isRequiredInValidation: true
      - id: insuranceNumber
        name: Insurance Number
        type: identifier/string
        isUnique: true
        isIndexed: true
        isShown: false             # hidden from public API, surfaced via admin API
        isEditable: false
        isRequiredInValidation: true
        regexValidation: '^[A-Z0-9]{10}$'
```

At runtime the IDs are accessed as `:system:email`, `:system:insuranceNumber`, etc.

### Adding custom *other* streams

Streams you need at the root of the tree (not under `:_system:account`) go under `custom.systemStreams.other`. They only support the core schema (no unicity / indexation / requiredness / visibility constraints).

```yaml
custom:
  systemStreams:
    other:
      - id: clientApp
        name: Client apps
        type: identifier/string
```

By default this list is empty.

### Modification caveats

Unicity and indexation only affect accounts **created after** the change — values recorded on pre-existing accounts are not retroactively synchronized into the platform DB. Flip these fields with care:

- `isUnique` / `isIndexed`: apply to new accounts, and to existing accounts only when the field gets updated through [`events.update`](/reference/#update-events).
- Removing a stream that already has events: the events become unreachable through the Pryv.io API. Prefer hiding (`isShown: false`) to deleting.

All core restarts re-load the unified config, so changes to `custom.systemStreams.*` take effect on the next `node bin/master.js` boot — in multi-core, restart each core in turn.


## Backward compatibility (historical)

Pryv.io 1.7 changed the system-stream ID prefix from `.` (dot) to `:_system:` / `:system:`. Up to v1.9.x a platform setting (`BACKWARD_COMPATIBILITY_SYSTEM_STREAMS_PREFIX`) accepted and returned IDs with the legacy dot prefix to ease client migration.

**In v2 that compatibility switch has been removed.** Clients must use the `:_system:` / `:system:` prefix exclusively. Operators upgrading v1 data to v2 via the [`dev-migrate-v1-v2`](https://github.com/pryv/dev-migrate-v1-v2) toolkit have the migration applied transparently during the restore; applications still emitting dot-prefixed IDs must be updated before cutover.

In v1.9.0 the `username` system stream was also removed — the username is now exposed through [access-info](/reference/#access-info).
