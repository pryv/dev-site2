---
title: 'Roles, scopes and local policy'
description: "The administrator roles of Pryv.io, the permissions each role gives, the scopes a grant can have (platform, region, zone, hosting, core), each core's local policy, and how roles are granted and revoked."
---


An administrator's power is a set of **grants** stored in the platform store under the account id: each grant is a **role** (a fixed bundle of permissions) at a **scope** (where it counts), optionally with an expiry. Each core computes, on every request, what the grants give on that core, under that core's own **local policy**. Every route checks one permission; the [Admin API reference](/reference-admin/) names it for each route.

How administrators sign in and how the first one gets a role: [First boot and administrators](/customer-resources/administrators/).

From open-pryv.io 2.0.0-rc.91 there is one role, `owner`, at scope `platform`. The other five roles, the narrower scopes, the local policy and role management over HTTP come with the release after 2.0.0-rc.91. With an unchanged configuration, an existing `owner` at `platform` keeps every permission on every core.

## Permissions

A permission is named `<capability>:<action>`. The list is a public contract: a name is added, never renamed nor reused with another meaning.

| Permission | What it allows |
|---|---|
| `setup:read` | read the setup checks |
| `setup:write` | replace the setup code, finish setup |
| `roles:read` | list the role rows, read one account's grants, find an account id by username |
| `roles:grant` | grant and revoke roles (step-up) |
| `claimCodes:mint` | mint claim codes (step-up) |
| `users:read` | list the accounts, read an account's usage, resolve an access id |
| `users:write` | create an account, reserve or update an account's platform fields |
| `users:delete` | delete an account's platform fields (step-up) |
| `users:resetMfa` | turn off an account's second factor |
| `cores:read` | list the cores |
| `config:read`, `config:write` | read and write the [platform configuration](/customer-resources/platform-configuration/) held in the platform store |
| `configEffective:read` | read a core's [effective configuration](/reference-system/#get-the-effective-configuration) |
| `certs:read`, `certs:write` | list certificates, force a renewal |
| `mail:read`, `mail:write` | read and change mail templates, send a test mail |
| `observability:read` | read the event-types and audit status |
| `migrations:read` | read the storage migrations status |
| `integrity:read` | run the platform integrity check |
| `audit:read` | read the [administration audit trail](/customer-resources/admin-audit/) |
| `erasures:read` | read the [erasure ledger](/reference-system/#erasures) |
| `extId:read`, `extId:write`, `extId:release` | read and change [external-id](/customer-resources/external-ids/) namespaces, release an id |
| `autoDeletion:clear` | [stop a pending deletion](/reference-system/#stop-a-pending-deletion) |
| `delegation:write` | the calls between cores of account delegation (admin key only) |
| `oauthClients:read`, `oauthClients:review` | read OAuth clients, review them ([OAuth app review](/customer-resources/oauth-app-review/)) |
| `publishers:read`, `publishers:review` | read and decide about app publishers |

Also defined, for administration surfaces that no route of this release serves with a session yet: `invitations:read`, `invitations:write`, `cores:write`, `dns:read`, `dns:write`, `observability:write`, `oauthClients:write`, `bootstrap:issue`.

## Roles

| Role | Permissions |
|---|---|
| `owner` | every permission |
| `operator` | `setup:read`, `roles:read`, `users:read`, `invitations:read`, `cores:read`, `cores:write`, `config:read`, `config:write`, `configEffective:read`, `certs:read`, `certs:write`, `dns:read`, `dns:write`, `mail:read`, `mail:write`, `observability:read`, `observability:write`, `migrations:read`, `integrity:read`, `extId:read`, `extId:write`, `oauthClients:read`, `publishers:read` |
| `support` | `users:read`, `users:write`, `users:delete`, `users:resetMfa`, `invitations:read`, `invitations:write`, `extId:read`, `extId:release`, `autoDeletion:clear` |
| `auditor` | `setup:read`, `roles:read`, `users:read`, `invitations:read`, `cores:read`, `config:read`, `configEffective:read`, `certs:read`, `dns:read`, `mail:read`, `observability:read`, `migrations:read`, `integrity:read`, `audit:read`, `erasures:read`, `extId:read`, `oauthClients:read`, `publishers:read` |
| `app-reviewer` | `oauthClients:read`, `oauthClients:write`, `oauthClients:review`, `publishers:read`, `publishers:review` |
| `viewer` | `cores:read`, `config:read`, `configEffective:read`, `certs:read`, `dns:read`, `mail:read`, `observability:read`, `migrations:read`, `integrity:read`, `oauthClients:read`, `publishers:read` |

Only `owner` holds `roles:grant`, `claimCodes:mint`, `setup:write`, `delegation:write` and `bootstrap:issue`. An unknown role in a role row gives nothing.

**Step-up.** `roles:grant`, `claimCodes:mint` and `users:delete` need a second factor younger than `admin.session.stepUpMinutes`, whatever the role (see [step-up](/customer-resources/administrators/#administrator-sessions)).

## Scopes

| Scope | Counts on |
|---|---|
| `platform` | every core |
| `region:<id>` | the cores whose hosting is in that region of the `hostings` hierarchy |
| `zone:<id>` | the cores whose hosting is in that zone |
| `hosting:<id>` | the cores of that hosting (`core.hosting`, `default` when unset) |
| `core:<id>` | that core (`core.id`) |

An id is 1 to 128 of `A-Z a-z 0-9 . _ -`. A core's place is read from its `core.id`, its `core.hosting` and the `hostings` hierarchy (regions, then zones, then hostings). An id that the hierarchy or the core list does not know never matches: such a grant is an **orphan** and gives nothing (the role list and `bin/admin.js roles list` show it with `scopeState: orphan`). Without a `hostings` hierarchy only `platform`, `hosting:default` and `core:<id>` can match.

Boot and `bin/check-config.js` refuse a `hostings` hierarchy in which a zone key appears in two regions or a hosting key in two zones: a `zone:` or `hosting:` scope would be ambiguous. Rename the duplicate before upgrading.

What a grant gives on a core:

1. **Platform-wide writes** (`roles:grant`, `claimCodes:mint`, `setup:write`, `config:write`, `dns:write`, `mail:write`, `observability:write`, `extId:write`, `cores:write`, `bootstrap:issue`, `delegation:write`) come only from grants at scope `platform`. So only a platform owner manages roles and mints claim codes.
2. **OAuth client and publisher permissions** (`oauthClients:*`, `publishers:*`) come only from grants at scope `platform` or `region:<r>`. A region grant reaches only the clients and publishers whose `regions` are all `r` (see [OAuth app review](/customer-resources/oauth-app-review/#review-over-http)).
3. **Every other permission** comes from a grant whose scope covers the core serving the call.

A grant at `core:core-2` with role `support` therefore lets its holder reset second factors and read accounts on `core-2` only, and gives nothing on the other cores. A session still opens on any core for an account that holds an active grant: the session answer lists the permissions of its roles not held on this core under `denied`, with `reason: scope`.

Because a grant may give a permission on this core only, the account routes keep to this core for a session: `PUT /system/users` answers 404 for a username with no account on this core, `POST /system/users/validate` refuses a `core` other than this one before anything is reserved, and `GET /system/accesses/{accessId}` on a multi-core platform answers 404 for an access of another core's account. The admin key keeps the platform-wide behaviour.

## Local policy

`admin.localPolicy` is set in a core's own configuration file, never in the platform store: any core can write a role row, only this core's file protects it. Cores holding different policies is expected (for example a core under a stricter regulation).

```yaml
admin:
  localPolicy:
    acceptReplicatedGrants: true
    requireLocalScope: [users:read, users:delete]
    localGrants:
      - userId: cj5d2kxvv0001example
        role: support
```

- **`acceptReplicatedGrants`** (default `true`): `false` means the grants of the platform store give nothing on this core; only `localGrants` do.
- **`requireLocalScope`** (default `[]`): permission names that only this core's `localGrants` give, whatever the scope of a replicated grant.
- **`localGrants`** (default `[]`): `{ userId, role }`, on this core only. The role's permissions minus the platform-wide writes and minus the OAuth client and publisher permissions. A local grant counts only for an account that also holds an active grant in the platform store (its session and its revocation live there); for any other account it gives nothing.

So on a core with `acceptReplicatedGrants: false` no session holds the OAuth client and publisher permissions: review apps on a core that accepts replicated grants. A permission refused by the policy is listed in the session's `denied` with `reason: local-policy`. The session read and the portal context give this core's policy when it is not the default, with the roles it grants the caller locally (never other accounts' grants).

The policy binds administrator sessions, never the admin key nor a setup session (the admin key's reach is [`auth.adminAccessKeyScope`](/customer-resources/administrators/#the-admin-key-authadminaccesskeyscope)). The core logs the effective policy at boot, without account ids. Boot and `bin/check-config.js` refuse an invalid one (unknown keys, an unknown permission name, a malformed account id or role) and warn about a `requireLocalScope` entry that no local grant can give.

## Managing roles

| Act | HTTP | Shell |
|---|---|---|
| list every role row | [`GET /system/admin/roles`](/reference-admin/#list-roles) | `node bin/admin.js roles list` |
| one account's grants | [`GET /system/admin/roles/{userId}`](/reference-admin/#get-an-accounts-roles) | |
| account id from a username | [`GET /system/admin/roles/by-username/{username}`](/reference-admin/#get-an-accounts-roles-by-username), on the account's home core | |
| grant a role at a scope | [`PUT /system/admin/roles/{userId}`](/reference-admin/#grant-a-role) `{ role, scope, expiresAt? }` | `node bin/admin.js roles grant <userId\|username> --role <r> --scope <s> [--expires 30d]` |
| revoke | [`DELETE /system/admin/roles/{userId}?role=&scope=`](/reference-admin/#revoke-roles) | `node bin/admin.js roles revoke <userId\|username> [--role <r>] [--scope <s>]` |
| give a role to someone not known yet | [claim code](/customer-resources/administrators/#claim-codes) at that role and scope | `node bin/admin.js claim-code --role <r> --scope <s>` |
| stop an account's sessions | | `node bin/admin.js sessions revoke <userId\|username>` |

Role rows never hold a username: a grant names the account id, which `GET /system/admin/roles/by-username/{username}` gives on the account's home core (elsewhere it answers 400 with the home core's URL). Granting a role that the account already holds at the same scope replaces that grant (to change its expiry, for example). `expiresAt` is in milliseconds since the epoch, in the future. A revocation without `role` removes every grant of the account; with `role` (and optionally `scope`) only those. Revoking a grant takes effect at the next request, on every core.

Granting and revoking need `roles:grant` with a recent second factor, or the admin key (granting is refused to the admin key under `break-glass`; revoking and listing are break-glass routes). The last lasting owner grant is protected: see [claim codes](/customer-resources/administrators/#claim-codes).

Every grant, revocation and claim is recorded in the [platform trail](/customer-resources/admin-audit/) of the core that served it, in the acting administrator's own trail and, when that account is on this core, in the grantee's trail (`admin.role.granted`, `admin.role.revoked`).
