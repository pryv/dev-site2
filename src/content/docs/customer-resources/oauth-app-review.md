---
title: 'OAuth control levels and app review'
description: "How a Pryv.io operator controls which OAuth apps may ask users for consent: registration modes, the validation level and badge of every app, per-level policies, what users and account apps see, and reviewing apps and publishers over HTTP."
---


On a self-hosted platform the operator's policy is the trust anchor for which apps may ask users for consent: the operator chooses who may register apps, what an unreviewed app may do, and who reviews. This page is for operators; the OAuth flow itself is described in [OAuth2 app authorization](/customer-resources/auth-oauth2/), and every configuration key in the [OAuth2 operator guide](https://github.com/pryv/open-pryv.io/blob/master/docs/oauth2.md#clientregistration-registration-mode-and-validation-levels).

The registration modes, the validation levels, the per-level policies and the badges come with open-pryv.io 2.0.0-rc.91. The review over HTTP and the current validation of granted apps come with the release after 2.0.0-rc.91.

## Registration modes

`oauth.clientRegistration.mode`, the same on every core:

- **`curated`** (the default): the operator registers every client with `bin/oauth-client.js`. An upgraded platform with an unchanged configuration behaves as before. A client a developer registered (`origin: developer`, left from a `delegated` period) is **not served** while the mode is `curated`: `/oauth2/authorize` redirects back with `unauthorized_client`, the consent answers `403 access_denied` with `reason: developer-clients-not-served`, and its refresh is refused. Its row and grants are kept: switching back to `delegated` serves it again.
- **`delegated`**: Pryv.io accounts may also register registry clients (`origin: developer`, owned by the registering account), under the operator's policy below. The core refuses to boot with it when no OAuth extension is installed. The registration by a developer comes with the developer API of a later release: today no command creates a developer's client.
- **`oauth.clientRegistration.whoMayRegister`** (`delegated` only): `validatedPublishers` (the default: only accounts whose publisher the operator validated) or `anyAccount` (the boot logs a warning).

Anonymous dynamic client registration (RFC 7591, `POST /oauth2/register`) is not offered: `mode: open`, and any other value, is refused at boot and by `bin/check-config.js`.

## Validation levels and badges

The core decides, for every registry client, who vouches for it; the consent screen shows it as a badge:

| Client | Level | Badge |
|---|---|---|
| registered by the operator (`origin` absent or `operator`) | `appValidated` | App Validated |
| `origin: developer`, its app review passed and no reviewed field changed since | `appValidated` | App Validated |
| `origin: developer`, its owner is a validated publisher | `publisherValidated` | Publisher Validated |
| `origin: developer`, otherwise | `nonValidated` | Non-Validated |
| [client metadata document](/customer-resources/auth-oauth2/#client-metadata-documents), `oauth.clientMetadataDocuments.mode: allowList`, its host listed in `allowedHosts` and not in `deniedHosts` | `publisherValidated` | Publisher Validated |
| client metadata document, otherwise | `nonValidated` | Non-Validated |

**An app review** stores the digest of the reviewed fields with a review version. Version 1 covers the redirect URIs, keys, scope, audiences, grant types, roles and lifetimes, the display identity (names, description, logo, home, policy and terms URLs), and what else changes what the app does or who stands behind it (insecure redirects, subject type, `maxEntries`, DPoP binding, token response extras, application type, kind, CMC offers, the owner). Not covered: the regions, the status, the secrets (a rotation keeps the badge), contacts and `softwareId`. A client whose reviewed fields changed is not App Validated until reviewed again. A review is always compared with the list of its own version, so an upgrade never downgrades a reviewed app.

**A publisher** is the account that owns a developer's client. Its status is a platform row: `validated` makes its apps Publisher Validated; absent, `none`, `pending` or `suspended`, it is not validated. Its display name (at most 128 characters) is answered only once validated.

The level is decided again at the consent and at each refresh. It is answered to the consent screen in the offer (`client.validation = { level, publisher?: { name?, validated }, validatedAt? }`, and `client.origin: "developer"` for a developer's client), and stamped on the grant and its sessions (`clientData.oauth.client.validation.level`).

## Per-level policies

`oauth.clientRegistration.levels.<level>`, for `nonValidated`, `publisherValidated` and `appValidated` (absent: everything allowed, as before):

- **`consent`**: `allow` (the default), `testers` or `refuse`.
  - `refuse`: `/oauth2/authorize` redirects back with `unauthorized_client`, the consent answers `403 access_denied` (`reason: client-not-validated`), and **the refresh of grants already given is refused too** (`400 unauthorized_client`; the refresh token is kept, so it works again if the level or the policy changes back).
  - `testers`: only the client's testers may consent, for now its owner account; anyone else gets `403 access_denied`, `reason: client-testers-only`. A client without an owner (an operator's or a metadata-document client) has no testers.
- **`scopeTemplate`**: the widest scope a client of that level may get, in the OAuth extension's grammar. A request that resolves to more is refused (`invalid_scope` at `/oauth2/authorize`; `400 invalid_scope`, `reason: client-scope-template`, at the consent). `openid` and `offline_access` are not restricted by it.
- **`maxGrants`** (1 to 100 000): how many accounts a client of that level may reach; a new account past the cap gets `403 access_denied`, `reason: client-grant-limit`. Approximate by design: accounts consenting at the same moment at the cap may all be refused, and an account's own revocation does not give its unit back (`bin/oauth-client.js purge-grants` and `revoke` do).

`testers`, `scopeTemplate` and `maxGrants` gate new consents only: grants already given keep their reach. To stop an app at once, [suspend](#review-over-http) it; to end its grants, `bin/oauth-client.js purge-grants`. A policy block with a problem is refused at boot, and read anywhere else as "every level refused". `bin/check-config.js` and the boot warn when `appValidated` is `testers` or `refuse` (the operator's own clients would be locked out). Keep the block identical on every core. The consent and refusal audit records carry `validationLevel`.

## What account apps show: current validation of granted apps

An account app lists the apps an account granted, with the badge of each as it stands now (an app may have lost its review, or be suspended, since the consent): [`POST /oauth2/clients/validation`](/reference/#methods-accesses-oauth2-clientsValidation) with `{ username, clientIds }` (at most 50) and the account's personal token. It answers, for each client the account granted, the `validation` block of the consent offer and `served` (`false` when the client is refused now). Ids the account did not grant are left out, without telling them apart from unknown ones.

## Review over HTTP

The review acts of `bin/oauth-client.js` and the decisions about publishers are also served over HTTP, for the administration portal and scripts. The same code writes the row as the CLI does. Creating or editing clients stays with the CLI.

| Route | Permission |
|---|---|
| [`GET /system/admin/oauth/clients`](/reference-admin/#list-oauth-clients) `?queue=&origin=&status=&limit=&skip=` | `oauthClients:read` |
| [`GET /system/admin/oauth/clients/{clientId}`](/reference-admin/#get-an-oauth-client) | `oauthClients:read` |
| [`POST .../clients/{clientId}/approve`](/reference-admin/#approve-an-oauth-client) `{ digest, reason? }` | `oauthClients:review` |
| [`POST .../clients/{clientId}/unvalidate`](/reference-admin/#withdraw-an-app-review) `{ reason }` | `oauthClients:review` |
| [`POST .../clients/{clientId}/suspend`](/reference-admin/#suspend-an-oauth-client) `{ reason }` | `oauthClients:review` |
| [`POST .../clients/{clientId}/resume`](/reference-admin/#resume-an-oauth-client) `{ reason? }` | `oauthClients:review` |
| [`GET /system/admin/oauth/publishers`](/reference-admin/#list-publishers) `?status=&limit=&skip=` | `publishers:read` |
| [`GET /system/admin/oauth/publishers/{userId}`](/reference-admin/#get-a-publisher) | `publishers:read` |
| [`PUT /system/admin/oauth/publishers/{userId}`](/reference-admin/#decide-about-a-publisher) `{ status, displayName?, regions?, reason }` | `publishers:review` |

They take an administrator session or the admin key in scope `full` (refused under `break-glass`); none asks for a second factor (each act is reversible and recorded). The `app-reviewer` role holds every permission above; `owner` too; `operator`, `auditor` and `viewer` hold the two reads.

**Region rule.** OAuth clients and publishers are platform-wide, so these permissions come only from grants at scope `platform` or `region:<r>` (a zone, hosting or core scope gives none, nor do a core's local grants; a core's local policy may still withhold them). Each route keeps to the rows the caller's grants cover: `platform` covers every row; `region:<r>` covers a row whose `regions` are all `r`; a row without `regions` needs `platform`. This holds for the lists and the reads too. A row out of reach answers 404, as a missing one.

**Approve what was read.** A client is answered with its review `digest`. `approve` takes that digest: without the current one it answers `409 stale-resource` and writes nothing, and its answer does not give the new digest (read the client again), so what is approved is always what was read. On a developer's client it records the app review; on a client under review it also approves the held changes. `unvalidate` withdraws a developer's client review. `resume` refuses a client under review or holding unapproved changes (approve it first). A row the registration rules now refuse answers `400 invalid-row` on `approve` and `unvalidate`.

**The queue** (`queue=true`) is computed at each read: developer clients whose review does not stand, and clients under review.

**A publisher decision** sets `status` (`none`, `pending`, `validated`, `suspended`), optionally `displayName` and `regions` (`null` removes them), with a `reason`. It counts for every client of the account, on every core, from its next consent offer or refresh. Creating a publisher row needs scope `platform`; a reviewer scoped to a region decides only the rows assigned to its region, and may only leave them in regions it covers.

**Audit.** Every act is recorded in the [platform trail](/customer-resources/admin-audit/) of the core that served it (who acted with which grant, the client or publisher, status and level before and after, the reason, and for `approve` the digest), in the acting administrator's own trail and, when that account is on this core, in the trail of the client's owner (`oauth.client.reviewed`) or of the publisher (`oauth.publisher.reviewed`). There, the actor is named `platform-administrator`, never the administrator's account, and the reviewer's reason is given as written: write it for the developer to read. The reads are not recorded.

## From a core's shell

`bin/oauth-client.js` `show` and `list` print each client's origin, owner and level, and `show` the review digest of a developer's client. `validate <clientId> --digest <digest>` records the app review of the row `show` printed (refused when it changed since), `unvalidate <clientId>` withdraws it, `suspend` and `resume` change its status. The full command set is in the [OAuth2 operator guide](https://github.com/pryv/open-pryv.io/blob/master/docs/oauth2.md#3-registering-application-accounts--binoauth-clientjs).
