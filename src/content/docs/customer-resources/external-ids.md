---
title: 'External ids: one account per record id'
description: How services link a third-party record id (an EHR patient id, for example) to exactly one Pryv.io account, platform-wide, without the platform ever seeing the id. Namespaces, blinding, claim and lookup, deletion, the privacy boundary and the operator tools.
---

<!-- TODO: add the open-pryv.io release that ships external ids once it is tagged. -->

An external id links a record id kept by a third-party system (an EHR patient id, for example) to one Pryv.io account. The platform guarantees one account per record id, across all cores, and never sees the record id itself.

## The problem

A medical practice runs two services on the same Pryv.io platform: a booking app and a follow-up app. Both know the patient by the same EHR patient id. Without help, each service creates its own account for the patient, or has to guess which existing account is the right one.

External ids solve this. The first service links the patient's EHR id to the patient's account. The second service asks the platform where that id lives and finds the same account's core. One patient, several services, one account.

## Namespaces

A namespace is a space of record ids that belong together: the patient ids of one EHR, for example. An account holds at most one id per namespace, and an id belongs to at most one account on the whole platform.

The platform administrator registers each namespace with the admin key (`auth.adminAccessKey`) in the `Authorization` header. The routes live under `/system/admin/ext-id-ns` on every core. Without the admin key they answer 404, so the surface is not advertised.

| Method | Path | Body | Response |
|---|---|---|---|
| `GET` | `/system/admin/ext-id-ns` | | `{ namespaces: [{ namespace, createdAt, label, defaultMode }] }` |
| `GET` | `/system/admin/ext-id-ns/:namespace` | | `{ namespace: { namespace, createdAt, label, defaultMode } }`, or 404 `unknown-resource` |
| `PUT` | `/system/admin/ext-id-ns/:namespace` | `{ label?, defaultMode? }` | 201 on create, 200 on update: `{ namespace: {...} }` |
| `DELETE` | `/system/admin/ext-id-ns/:namespace[?force=true]` | | 204, 404 `unknown-resource`, or 409 `external-id-namespace-in-use` |

- **Name**: 2 to 63 characters, lower-case letters, digits and `-`, starting with a letter or a digit (`^[a-z0-9][a-z0-9-]{1,62}$`).
- **Salt**: the server generates a random salt when it creates the namespace. The salt never changes and is never returned. A `PUT` on an existing namespace only updates its label and default mode.
- **`label`**: 1 to 80 characters, shown to users on confirmation screens. It defaults to the namespace name.
- **`defaultMode`**: `hint` (the default) or `forced`. It is used by the flows described in [Coming next](#coming-next).
- **Delete**: refused with `409 external-id-namespace-in-use` while ids are still claimed in the namespace. With `force=true` only the namespace row is deleted. Each core's [reconcile](#operators) then reports the local ids of that namespace.

Example:

```sh
ADMIN_KEY=...
curl -sS -X PUT https://core-a.example.com/system/admin/ext-id-ns/clinic-ehr \
  -H "Authorization: $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  --data-binary '{ "label": "Clinic patient record", "defaultMode": "hint" }'
```

## Blinding by the caller

The caller never sends the record id. For each namespace it keeps its own secret key, `K_namespace`, and sends a blinded value:

```
blindedValue = HMAC(K_namespace, recordId)
```

The key never reaches the platform. Send the value as base64url without padding, 16 to 64 bytes once decoded. HMAC-SHA-256 gives 32 bytes:

```js
const { createHmac } = require('node:crypto');
const blindedValue = createHmac('sha256', K_namespace).update(recordId).digest('base64url');
```

Sharing `K_namespace` between the caller's services is the caller's choice. It is what lets the second service find the account linked by the first. Every holder of the key can then look up and claim ids of that namespace.

Handle a blinded value like a secret. Until an account claims it, holding it is what lets an account claim the id.

## Claiming, listing, replacing, releasing

The account's ids are managed with a personal access token. An app or a shared access gets `403 forbidden`.

- [Claim an external id](/reference/#claim-an-external-id): `POST /account/external-ids` with `{ namespace, blindedValue }`. It answers `201` with `{ externalId: { namespace, claimedAt } }` when the id is linked now, and `200` with the same body when the account already holds that exact value. It answers `409 external-id-already-claimed` with `data: { namespace, reason }`: `value-taken` when another account, on any core, holds the id (the error never says which), `namespace-taken` when the account already holds another id in that namespace.
- [List external ids](/reference/#list-external-ids): `GET /account/external-ids` returns `{ externalIds: [{ namespace, claimedAt }] }`. It never returns a blinded value.
- [Replace an external id](/reference/#replace-an-external-id): `PUT /account/external-ids/:namespace` with `{ blindedValue }`. The new id is linked, then the old one is released. When the account holds nothing in the namespace it behaves as a claim.
- [Release an external id](/reference/#release-an-external-id): `DELETE /account/external-ids/:namespace` answers `{ released: true }`, also when nothing was held.

An unknown namespace or a malformed value answers `400 invalid-parameters-format`. No error ever echoes the value.

## Finding the core that holds an id

A service that knows the record id computes its blinded value and asks the register surface which core holds it:

```sh
curl -sS -X POST https://reg.example.com/ext-id/cores \
  -H "Content-Type: application/json" \
  --data-binary '{ "namespace": "clinic-ehr", "blindedValue": "5axJiZtfRrrFmLoDoJc9LWUadGJBz-ByjoE8SAAHBz4" }'
```

See [Get core holding an external id](/reference-system/#get-core-holding-an-external-id). No authentication is needed. The answer is `200 { "server": "<core base URL>" }`, or `404 unknown-resource`: an unknown namespace and an id nobody claimed give the same answer. It is a `POST` so the value never appears in a URL. The answer names a core, never an account: data reaches the account only through an access its holder grants.

Lookups and refused claims share a budget per client address (an IPv4 address, or the /64 of an IPv6 address), kept by each core: at most 10 in a one-minute window. Each lookup counts. A refused claim or replace counts, a successful one does not. Past the budget the lookup or claim is not run and answers `429 too-many-attempts` with `Retry-After`. Whoever holds a namespace key can compute candidate values for a small id space, and the budget bounds how fast one address can test them. See also [Limits at a glance](/customer-resources/rate-limiting/#limits-at-a-glance).

## Account deletion

When an account is deleted, its ids are released at once and can be claimed again by another account. The erasure keeps no trace of them.

## Keeping the record id in the account

The index never holds the record id. A service that needs it later may store the plaintext record id as ordinary data in the user's own account (in an event, for example). It is then visible to the user like any other data of the account, and stays outside the index.

## Privacy boundary

- **What the platform stores.** The replicated index maps a blinded id to the core that holds it, never to the account. Only the home core knows which of its accounts holds an id: it keeps the account, the blinded value and the claim date in its own database. In cleartext PII mode (`platform.piiMode: cleartext`) the index stores the blinded values and the namespace salts as they are: they are pseudonyms, but whoever reads a copy of the index and also holds blinded values from elsewhere (an invitation link, for example) can match them. In hashed mode (the default) they are additionally keyed by the platform pepper.
- **What a core alone learns.** From the index, how many ids each core holds in each namespace, and nothing about the record ids.
- **What a core plus `K_namespace` learns.** It can compute the blinded value of a record id, so it can test whether that id is on the platform and on which core. Only the home core can also tell which of its accounts holds it.
- **How data flows.** The index never carries an account. Data reaches an account only through an access its holder granted.

What the platform never does: store the plaintext record id, or put a blinded value in a URL, a log or a listing.

### The residual

Whoever holds a blinded value before the patient claims it (for example from an unused invitation link) can claim it first with their own account. The patient then cannot link that id while that account holds it. This is a denial, never a data flow: the first claimer gets no data of the patient, and services that look the id up find the claimer's core, not the patient's data.

## Coming next

Not released yet, and documented here when they ship:

- fields of the authorization request and of the registration that carry an external id, with the `hint` and `forced` modes of a namespace, and a hosted confirmation screen showing the namespace's label to the user;
- a release of an id by the platform administrator, for an id claimed by the wrong account, with a notice to the account that held it.

## Operators

Run the reconcile on each core:

```sh
node bin/reconcile-user-cores.js --ext-ids [--old-pepper <BASE64>] [--dry-run]
```

It brings the core's local table and the replicated index back in line: stale index rows deleted, missing rows claimed again, ids of deleted accounts released, ids another core holds dropped locally, ids of a deleted namespace reported. It never touches rows of other cores, and it is safe to run again. Run it with that core's API stopped: a claim or a release in flight during the run can be undone by it. When the core's local table is empty while the index holds ids for the core, it refuses to delete them (exit code 3): that usually means the table was lost, and deleting would free every id of the core. Restore the table, or pass `--force-empty-local` if it is really meant to be empty. Run it:

- after a restore;
- after a crash during a claim;
- before moving a core;
- on every core after a switch between cleartext and hashed PII mode. For a switch from hashed to cleartext, add `--old-pepper` with the retired pepper.

`bin/platform-pii-rotate.js` refreshes each core's ids itself when it rotates the pepper.

The namespace rows, with their salts, are part of the platform backup of [`bin/backup.js`](/customer-resources/backup/). A lost salt orphans every id of its namespace. The index rows are not backed up: each core's reconcile rebuilds them from its local table. A restore never overwrites a live namespace whose salt differs from the backup: it keeps the live one and reports it.
