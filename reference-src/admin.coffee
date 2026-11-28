# Admin API reference: the `/system/*` administration routes served by every
# core, and the operator command-line tools. Rendered by /reference-admin and
# listed in llms-full.txt. Not published as OpenAPI.

# The credential paragraph of a method: who may call it.
# `permission`: what an administrator session needs; `breakGlass`: the admin key
# still reaches the route with `auth.adminAccessKeyScope: break-glass`.
credential = (permission, breakGlass) ->
  key = if breakGlass then "the admin key (also under `break-glass`)" else "the admin key (scope `full` only)"
  return "**Credential:** #{key}, or an [administrator session](#authentication) holding `#{permission}`."

stepUp = "A session needs a recent second factor for this act ([step-up](#step-up)): without one the call answers `403 forbidden` with `data.stepUp: true`."

keyOnly = (breakGlass) ->
  extra = if breakGlass then " (also under `break-glass`)" else ""
  return "**Credential:** the admin key only#{extra}."

sinceSetup = "From open-pryv.io 2.0.0-rc.91."
sinceNext = "From the release after open-pryv.io 2.0.0-rc.91."

homeCore = "A personal token is accepted on its account's home core only: elsewhere the call answers `400 invalid-operation` with `data.homeCoreUrl`, the URL of the core to send it to."

module.exports = exports =
  id: "admin"
  title: "Admin API"
  sections: [
    id: "overview"
    title: "Admin API"
    description: """
                 The admin API is the operator-facing surface of a Pryv.io core: a set of `/system/*` HTTP routes served by every core, complemented by the `bin/*.js` operator tools (see [Operator CLIs](#operator-clis)).

                 There is no separate administration server, no config-leader and no admin-panel GUI: platform-wide state lives in the platform store, which every core reads, and the administration portal (when configured) calls these routes.

                 The account, erasure, external-id, auto-deletion and effective-configuration routes are documented in the [System API reference](/reference-system/#admin); they take the same credentials, described below.

                 Guides: [First boot and administrators](/customer-resources/administrators/), [Roles, scopes and local policy](/customer-resources/admin-roles/), [Administration audit trail](/customer-resources/admin-audit/), [Platform configuration](/customer-resources/platform-configuration/), [OAuth control levels and app review](/customer-resources/oauth-app-review/).
                 """
  ,
    id: "authentication"
    title: "Authentication"
    description: """
                 A `/system` request carries one of these credentials in the `Authorization` header:

                 - **The admin key**, verbatim (the `auth.adminAccessKey` value, not a `Bearer` token). It holds every permission. With `auth.adminAccessKeyScope: break-glass` it reaches only the routes marked "also under `break-glass`" below; a `/system` path no route serves is refused too. The key is required at boot and must be identical on every core of a platform.
                 - **An administrator session** (from open-pryv.io 2.0.0-rc.91): `Authorization: AdminSession <token>`, opened with [Open an administrator session](#open-an-administrator-session) once setup is finished. On each request the core reads the account's role row and computes the permissions the account holds **on this core** (its grants whose scope covers this core, under this core's local policy: see [Roles, scopes and local policy](/customer-resources/admin-roles/)); the route's permission must be among them.
                 - **A setup session**, `Authorization: SetupSession <token>`, while setup is pending, on the routes that say so. It holds every permission.

                 Some routes take their own credential: a personal token of the account (the session, claim and first-administrator routes), a one-time join token (`POST /system/admin/cores/ack`), or none (`GET /system/setup/status`, `GET /system/portal/settings`).

                 ```bash
                 curl -i -H 'Authorization: <adminAccessKey>' \\
                   "https://{core}.{domain}/system/admin/cores"
                 curl -i -H 'Authorization: AdminSession <token>' \\
                   "https://{core}.{domain}/system/admin/cores"
                 ```

                 **Refusals answer `404 unknown-resource`**, as an unknown route does: no credential, a wrong key, an unknown or ended session, a permission not held, the admin key outside its scope, a session while setup is pending. No hint is given to retry.

                 **Origin rule.** A call that carries an `Origin` header and is not authenticated by the admin key is accepted only from the core's own origin, the portal's origin (`portal.site` with the topology, or `portal.url`) or an origin listed in `portal.cors.allowedOrigins`, and gets CORS headers for that origin only. Admin-key calls and calls without `Origin` keep the API-wide behaviour.

                 **Lockdown.** A core's `admin.lockdown` may refuse the writes of a capability (`403 admin-lockdown-capability`) or of a platform configuration key (`403 admin-lockdown-key`), whatever the credential: see [Lockdown](/customer-resources/platform-configuration/#lockdown).
                 """
    sections: [
      id: "step-up"
      title: "Step-up"
      description: """
                   Granting or revoking roles (`roles:grant`), minting claim codes (`claimCodes:mint`), deleting an account's platform fields (`users:delete`) and writing the platform configuration keys marked so need, from an administrator session, a second factor younger than `admin.session.stepUpMinutes` (default 5). Without it the call answers `403 forbidden` with `data.stepUp: true`: sign in again, send the new personal token to [Confirm a second factor](#confirm-a-second-factor), then repeat the call. The admin key and the setup session never need one.
                   """
    ]
  ,
    id: "setup"
    title: "Setup"
    description: """
                 #{sinceSetup} The first boot of a fresh platform: the setup code, the setup session, the first administrator. See [First boot and administrators](/customer-resources/administrators/#setup-state). The built-in setup page `GET /system/setup/` (with `setup.js` and `setup.css`) is served without credential while setup is pending, and answers 404 after.
                 """
    sections: [
      id: "setup-status"
      type: "method"
      title: "Get the setup state"
      http: "GET /system/setup/status"
      description: """
                   Whether the platform waits for its first administrator. No credential. It does not say when setup was done. Not audited.
                   """
      result:
        http: "200 OK"
        properties: [
          key: "setup"
          type: "object"
          description: """
                       `state` (`pending` or `ready`), `codePending` (a valid setup code exists), `codeExpiresAt` (milliseconds since the epoch, or `null`), `mfaRequired` (administrators need a second factor), `setupPageUrl` and `portalUrl` (or `null`).
                       """
        ]
    ,
      id: "setup-checks"
      type: "method"
      title: "Get the setup checks"
      http: "GET /system/setup/checks"
      description: """
                   The checks the setup page shows: configuration, public address, DNS delegation, certificates and how they are issued, migrations, second factor, registration, portal, admin key scope. Not audited.

                   #{credential("setup:read", true)} A setup session too.
                   """
      result:
        http: "200 OK"
        properties: [
          key: "checks"
          type: "array of objects"
          description: """
                       One object per check: `id` (`config`, `topology`, `dns`, `dns-port`, `certificates`, `certificates-key`, `migrations`, `mfa`, `registration`, `portal`, `admin-key`), `status` (`ok`, `info`, `warn` or `blocking`), `title`, `detail`.
                       """
        ]
    ,
      id: "setup-session"
      type: "method"
      title: "Open a setup session"
      http: "POST /system/setup/session"
      description: """
                   Redeems the setup code for a setup session (2 hours). No credential. Limited to 10 tries per 15 minutes per core; the code stays valid past that. Only answered while setup is pending.
                   """
      params:
        properties: [
          key: "code"
          type: "string"
          description: """
                       The setup code. Case, dashes and spaces are ignored; `O` reads as `0`, `I` and `L` as `1`.
                       """
        ]
      result:
        http: "201 Created"
        properties: [
          key: "setupSession"
          type: "object"
          description: """
                       `token` (use it as `Authorization: SetupSession <token>`) and `expiresAt`.
                       """
        ]
      errors: [
        key: "unknown-resource"
        http: "404"
        description: """
                     Wrong, used or expired code, or setup is not pending.
                     """
      ,
        key: "too-many-requests"
        http: "429"
        description: """
                     More than 10 tries in 15 minutes on this core; `Retry-After` says when to try again.
                     """
      ]
    ,
      id: "setup-first-admin"
      type: "method"
      title: "Make the first administrator"
      http: "POST /system/setup/first-admin"
      description: """
                   Gives role `owner` at scope `platform` to an account of this core, proved by its personal token. When administrators need a second factor, the sign-in behind the token must have passed it.

                   **Credential:** a setup session only.
                   """
      params:
        properties: [
          key: "username"
          type: "string"
          description: """
                       The account.
                       """
        ,
          key: "personalToken"
          type: "string"
          description: """
                       A personal token of that account, from a sign-in on this core.
                       """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "role"
          type: "object"
          description: """
                       `userId`, `grants` (`role`, `scope`, `grantedAt`, `grantedBy`, `via`, `expiresAt`), `updatedAt`.
                       """
        ]
      errors: [
        key: "unknown-resource"
        http: "404"
        description: """
                     The username and token do not prove a personal access of an account of this core.
                     """
      ,
        key: "forbidden"
        http: "403"
        description: """
                     The sign-in did not pass the second factor (`data.mfaRequired: true`).
                     """
      ]
    ,
      id: "setup-finish"
      type: "method"
      title: "Finish setup"
      http: "POST /system/setup/finish"
      description: """
                   Marks the platform ready: registration opens, the setup code and the setup session stop working, and the setup code file is deleted. With the setup session, a first administrator must exist; with the admin key, setup finishes without one (automated installs: the first administrator then comes from a [claim code](#mint-a-claim-code)). `node bin/admin.js setup finish` does the same from a core's shell.

                   **Credential:** a setup session, or the admin key (scope `full` only).
                   """
      result:
        http: "200 OK"
        properties: [
          key: "setup"
          type: "object"
          description: """
                       `state` (`ready`) and `readyAt`.
                       """
        ]
      errors: [
        key: "invalid-operation"
        http: "400"
        description: """
                     Setup is not pending, or (setup session) there is no first administrator yet.
                     """
      ]
    ,
      id: "setup-code"
      type: "method"
      title: "Replace the setup code"
      http: "POST /system/admin/setup/code"
      description: """
                   Mints a new setup code, answered once; the previous one stops working. `node bin/admin.js setup-code --new` does the same from a core's shell. Answered with `Cache-Control: no-store`.

                   #{credential("setup:write", true)} A setup session too.
                   """
      result:
        http: "201 Created"
        properties: [
          key: "setupCode"
          type: "object"
          description: """
                       `code` (grouped for display) and `expiresAt`.
                       """
        ]
      errors: [
        key: "invalid-operation"
        http: "400"
        description: """
                     Setup is not pending: there is no setup code to replace.
                     """
      ]
    ]
  ,
    id: "admin-sessions"
    title: "Administrator sessions"
    description: """
                 #{sinceSetup} See [Administrator sessions](/customer-resources/administrators/#administrator-sessions). A session lasts `admin.session.ttlMinutes` (60); only its SHA-256 is stored, in the platform store, so every core accepts it. Sessions open once setup is finished.
                 """
    sections: [
      id: "session-create"
      type: "method"
      title: "Open an administrator session"
      http: "POST /system/admin/session"
      description: """
                   Opens a session for an account that holds an active grant (any role, any scope, even one that gives nothing on this core). With `services.mfa` on and `admin.session.requireMfa: true` (the default), the sign-in behind the token must have passed its second factor.

                   **Credential:** the account's personal token in the `Authorization` header (raw or `Bearer`). An app or shared access opens nothing. #{homeCore}
                   """
      params:
        properties: [
          key: "username"
          type: "string"
          description: """
                       The account.
                       """
        ]
      result:
        http: "201 Created"
        properties: [
          key: "adminSession"
          type: "object"
          description: """
                       `token` (use it as `Authorization: AdminSession <token>`), `expiresAt`, `userId`, `homeCore`, `mfaAt` (when the second factor was passed, or `null`), `stepUpFresh`, `permissions` (held on this core) and `denied` (from the release after 2.0.0-rc.91: `[{ permission, reason }]`, the permissions of the account's roles not held on this core, `reason` `scope` or `local-policy`).
                       """
        ]
      errors: [
        key: "unknown-resource"
        http: "404"
        description: """
                     The token is not a personal token of the account, or the account holds no active grant.
                     """
      ,
        key: "forbidden"
        http: "403"
        description: """
                     The sign-in did not pass the second factor (`data.mfaRequired: true`).
                     """
      ,
        key: "invalid-operation"
        http: "400"
        description: """
                     Setup is not finished, or the account's home core is another one (`data.homeCoreUrl`).
                     """
      ]
    ,
      id: "session-get"
      type: "method"
      title: "Read the administrator session"
      http: "GET /system/admin/session"
      description: """
                   What the session holds on the core that answers. Not audited.

                   **Credential:** an administrator session.
                   """
      result:
        http: "200 OK"
        properties: [
          key: "adminSession"
          type: "object"
          description: """
                       `userId`, `homeCore`, `mfaAt`, `createdAt`, `expiresAt`, `stepUpFresh`, `permissions` and `denied` (on this core), `grants` (each with `scopeState`: `ok`, or `orphan` when its scope names nothing the platform knows), and `localPolicy` when this core's policy is not the default (`acceptReplicatedGrants`, `requireLocalScope`, `localRoles`: the roles it grants this account locally).
                       """
        ]
    ,
      id: "session-delete"
      type: "method"
      title: "End the administrator session"
      http: "DELETE /system/admin/session"
      description: """
                   **Credential:** an administrator session.
                   """
      result:
        http: "204 No Content"
    ,
      id: "session-renew"
      type: "method"
      title: "Renew the administrator session"
      http: "POST /system/admin/session/renew"
      description: """
                   Extends the session by `admin.session.ttlMinutes`, proved by a personal token of the session's own account. Sent to the session's home core.

                   **Credential:** an administrator session, and the personal token in the body.
                   """
      params:
        properties: [
          key: "personalToken"
          type: "string"
          description: """
                       A personal token of the session's account.
                       """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "adminSession"
          type: "object"
          description: """
                       `expiresAt` and `mfaAt`.
                       """
        ]
      errors: [
        key: "invalid-operation"
        http: "400"
        description: """
                     Not the session's home core (`data.homeCoreUrl`).
                     """
      ]
    ,
      id: "session-step-up"
      type: "method"
      title: "Confirm a second factor"
      http: "POST /system/admin/session/step-up"
      description: """
                   Records a recent second factor on the session, for the acts that need [step-up](#step-up): sign in again (with the second factor), then send that new personal token. Sent to the session's home core. A core accepts a second factor stamped up to 60 seconds in its future.

                   **Credential:** an administrator session, and the personal token in the body.
                   """
      params:
        properties: [
          key: "personalToken"
          type: "string"
          description: """
                       A personal token of the session's account, from a sign-in younger than `admin.session.stepUpMinutes`.
                       """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "adminSession"
          type: "object"
          description: """
                       `expiresAt` and `mfaAt`.
                       """
        ]
      errors: [
        key: "forbidden"
        http: "403"
        description: """
                     The sign-in behind the token is not recent enough (`data.stepUp: true`).
                     """
      ,
        key: "invalid-operation"
        http: "400"
        description: """
                     Not the session's home core (`data.homeCoreUrl`).
                     """
      ]
    ]
  ,
    id: "roles"
    title: "Roles and claim codes"
    description: """
                 Roles `owner`, `operator`, `support`, `auditor`, `app-reviewer` and `viewer` at a scope `platform`, `region:<id>`, `zone:<id>`, `hosting:<id>` or `core:<id>` (an id is 1 to 128 of `A-Z a-z 0-9 . _ -`). See [Roles, scopes and local policy](/customer-resources/admin-roles/). Role rows name accounts by id only. Claim codes, the role list and revocation come with open-pryv.io 2.0.0-rc.91 (role `owner` at `platform` only); the other roles and scopes, the one-account reads and the grant route with the release after 2.0.0-rc.91.
                 """
    sections: [
      id: "claim-codes-create"
      type: "method"
      title: "Mint a claim code"
      http: "POST /system/admin/claim-codes"
      description: """
                   A one-time code that gives a role at a scope to the account that redeems it with [Claim a role](#claim-a-role). Answered once (only its SHA-256 is stored), with `Cache-Control: no-store`. Not with the setup session: a code outlives it.

                   #{credential("claimCodes:mint", true)} #{stepUp}
                   """
      params:
        properties: [
          key: "role"
          type: "string"
          optional: true
          description: """
                       The role the code gives. Defaults to `owner`.
                       """
        ,
          key: "scope"
          type: "string"
          optional: true
          description: """
                       The scope of the grant. Defaults to `platform`.
                       """
        ,
          key: "ttlMinutes"
          type: "number"
          optional: true
          description: """
                       Lifetime, a whole number of minutes from 1 to 1440. Defaults to 15.
                       """
        ]
      result:
        http: "201 Created"
        properties: [
          key: "claimCode"
          type: "object"
          description: """
                       `code`, `role`, `scope`, `expiresAt`.
                       """
        ]
      errors: [
        key: "invalid-parameters-format"
        http: "400"
        description: """
                     Unknown role or scope, a `ttlMinutes` out of range, or another parameter.
                     """
      ]
    ,
      id: "roles-claim"
      type: "method"
      title: "Claim a role"
      http: "POST /system/admin/roles/claim"
      description: """
                   Redeems a claim code for the signed-in account: the code is consumed (of two concurrent claims exactly one wins) and its grant written, `via: claim-code`. The same second-factor rule as for [opening a session](#open-an-administrator-session) applies. 10 tries per 15 minutes per account.

                   **Credential:** the account's personal token in the `Authorization` header. #{homeCore}
                   """
      params:
        properties: [
          key: "username"
          type: "string"
          description: """
                       The account.
                       """
        ,
          key: "code"
          type: "string"
          description: """
                       The claim code.
                       """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "role"
          type: "object"
          description: """
                       `userId`, `grants`, `updatedAt`.
                       """
        ]
      errors: [
        key: "unknown-resource"
        http: "404"
        description: """
                     Unknown, used or expired code, or the token does not prove a personal access of the account.
                     """
      ,
        key: "forbidden"
        http: "403"
        description: """
                     The sign-in did not pass the second factor (`data.mfaRequired: true`).
                     """
      ,
        key: "too-many-requests"
        http: "429"
        description: """
                     More than 10 tries in 15 minutes for this account.
                     """
      ]
    ,
      id: "roles-list"
      type: "method"
      title: "List roles"
      http: "GET /system/admin/roles"
      description: """
                   Every role row of the platform. Not audited.

                   #{credential("roles:read", true)}
                   """
      result:
        http: "200 OK"
        properties: [
          key: "roles"
          type: "array of objects"
          description: """
                       Per account: `userId`, `username` (when the account is on this core, else `null`), `grants` (each with `scopeState`: `ok` or `orphan`), `updatedAt`, `sessionsRevokedAt`.
                       """
        ]
    ,
      id: "roles-get"
      type: "method"
      title: "Get an account's roles"
      http: "GET /system/admin/roles/{userId}"
      description: """
                   #{sinceNext} One account's grants. Not audited.

                   #{credential("roles:read", true)}
                   """
      params:
        properties: [
          key: "userId"
          type: "string"
          http:
            text: "set in request path"
          description: """
                       The account id.
                       """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "role"
          type: "object"
          description: """
                       `userId`, `username` (or `null`), `grants` (with `scopeState`), `updatedAt`, `sessionsRevokedAt`.
                       """
        ]
      errors: [
        key: "unknown-resource"
        http: "404"
        description: """
                     The account holds no role.
                     """
      ]
    ,
      id: "roles-get-by-username"
      type: "method"
      title: "Get an account's roles by username"
      http: "GET /system/admin/roles/by-username/{username}"
      description: """
                   #{sinceNext} The same answer, by username: how a username becomes the account id a grant needs. Answered by the account's home core only. Not audited.

                   #{credential("roles:read", false)}
                   """
      params:
        properties: [
          key: "username"
          type: "string"
          http:
            text: "set in request path"
          description: """
                       The username (any case).
                       """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "role"
          type: "object"
          description: """
                       `userId`, `username`, `grants` (empty when the account holds no role), `updatedAt`, `sessionsRevokedAt`.
                       """
        ]
      errors: [
        key: "invalid-operation"
        http: "400"
        description: """
                     The account's home core is another one (`data.homeCoreUrl`).
                     """
      ,
        key: "unknown-resource"
        http: "404"
        description: """
                     No such account.
                     """
      ]
    ,
      id: "roles-set"
      type: "method"
      title: "Grant a role"
      http: "PUT /system/admin/roles/{userId}"
      description: """
                   #{sinceNext} Grants a role at a scope to an account, or replaces the account's grant of that role and scope (to change its expiry, for example). Recorded as `via: grant` (`admin-key` with the key). Replacing the last lasting owner grant (`owner` at `platform`, no expiry) with an expiring one is refused.

                   #{credential("roles:grant", false)} #{stepUp}
                   """
      params:
        properties: [
          key: "userId"
          type: "string"
          http:
            text: "set in request path"
          description: """
                       The account id ([Get an account's roles by username](#get-an-accounts-roles-by-username) gives it).
                       """
        ,
          key: "role"
          type: "string"
          description: """
                       The role.
                       """
        ,
          key: "scope"
          type: "string"
          description: """
                       The scope.
                       """
        ,
          key: "expiresAt"
          type: "number"
          optional: true
          description: """
                       When the grant ends, in milliseconds since the epoch, in the future. Absent or `null`: no expiry.
                       """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "role"
          type: "object"
          description: """
                       The account's row after the grant, as [Get an account's roles](#get-an-accounts-roles) answers it.
                       """
        ]
      errors: [
        key: "invalid-parameters-format"
        http: "400"
        description: """
                     A malformed user id, an unknown role or scope, an `expiresAt` not in the future, or another parameter.
                     """
      ,
        key: "invalid-operation"
        http: "400"
        description: """
                     `data.id: last-owner`: the change would leave the platform without a lasting owner grant.
                     """
      ]
    ,
      id: "roles-delete"
      type: "method"
      title: "Revoke roles"
      http: "DELETE /system/admin/roles/{userId}"
      description: """
                   Removes all the account's grants (its row is deleted), or with `role` (and optionally `scope`) only those. Takes effect at the next request on every core. The last lasting owner grant cannot be revoked (`node bin/admin.js roles revoke --force` can).

                   #{credential("roles:grant", true)} #{stepUp}
                   """
      params:
        properties: [
          key: "userId"
          type: "string"
          http:
            text: "set in request path"
          description: """
                       The account id.
                       """
        ,
          key: "role"
          type: "string"
          optional: true
          http:
            text: "query parameter"
          description: """
                       Only the grants of this role.
                       """
        ,
          key: "scope"
          type: "string"
          optional: true
          http:
            text: "query parameter"
          description: """
                       With `role`: only the grant at this scope.
                       """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "revoked"
          type: "boolean"
          description: """
                       `true`.
                       """
        ]
      errors: [
        key: "unknown-resource"
        http: "404"
        description: """
                     Nothing matched: no role row, or no grant of that role and scope.
                     """
      ,
        key: "invalid-operation"
        http: "400"
        description: """
                     `data.id: last-owner`.
                     """
      ]
    ]
  ,
    id: "audit"
    title: "Administration audit"
    description: """
                 #{sinceNext} Each core stores the records of the administration acts it serves in its platform trail. See [Administration audit trail](/customer-resources/admin-audit/).
                 """
    sections: [
      id: "audit-get"
      type: "method"
      title: "Read the platform trail"
      http: "GET /system/admin/audit"
      description: """
                   The records of this core's platform trail, most recent first. Each core answers for its own trail: read every core. Not itself audited. Answered with `Cache-Control: no-store`.

                   With a `subject` or `target` filter, at most 20 000 records are read to answer a page; when that stops the read before the page is full, the answer carries `scanLimitReached: true` and `scannedToTime`: continue with `toTime` set to that value and `skip: 0`, dropping by `id` the records already read (`toTime` is inclusive).

                   #{credential("audit:read", false)}
                   """
      params:
        properties: [
          key: "fromTime"
          type: "number"
          optional: true
          http:
            text: "query parameter"
          description: """
                       Only the records at or after this time, in seconds since the epoch.
                       """
        ,
          key: "toTime"
          type: "number"
          optional: true
          http:
            text: "query parameter"
          description: """
                       Only the records at or before this time, in seconds since the epoch.
                       """
        ,
          key: "methodId"
          type: "string"
          optional: true
          http:
            text: "query parameter"
          description: """
                       Only the records of this method id (for example `system.roles.set`).
                       """
        ,
          key: "subject"
          type: "string"
          optional: true
          http:
            text: "query parameter"
          description: """
                       Only the acts of this administrator's account id, or of `admin-key`, `setup` or `cli`.
                       """
        ,
          key: "target"
          type: "string"
          optional: true
          http:
            text: "query parameter"
          description: """
                       Only the acts that name this value as their object: an account id, a username hash, a namespace...
                       """
        ,
          key: "limit"
          type: "number"
          optional: true
          http:
            text: "query parameter"
          description: """
                       Records per page, 1 to 1000. Defaults to 100.
                       """
        ,
          key: "skip"
          type: "number"
          optional: true
          http:
            text: "query parameter"
          description: """
                       Matching records to skip, 0 to 10000 (read further by narrowing `toTime`).
                       """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "auditEvents"
          type: "array of objects"
          description: """
                       The records: audit events whose `content.record` holds `subject` (`via`, `userId`, `sessionId`, `role`, `scope`, `localGrant`), `target`, `diff` and `result`.
                       """
        ,
          key: "limit"
          type: "number"
          description: """
                       The page size used.
                       """
        ,
          key: "skip"
          type: "number"
          description: """
                       The records skipped.
                       """
        ,
          key: "hasMore"
          type: "boolean"
          description: """
                       Matching records may follow this page.
                       """
        ,
          key: "scanLimitReached"
          type: "boolean"
          optional: true
          description: """
                       `true` when the read stopped at the scan limit (see above).
                       """
        ,
          key: "scannedToTime"
          type: "number"
          optional: true
          description: """
                       With `scanLimitReached`: the time of the last record read.
                       """
        ]
      errors: [
        key: "invalid-parameters-format"
        http: "400"
        description: """
                     A malformed parameter, or another parameter.
                     """
      ,
        key: "api-unavailable"
        http: "503"
        description: """
                     Audit is off on this core, or its audit storage does not keep the platform trail.
                     """
      ]
    ]
  ,
    id: "platform-config"
    title: "Platform configuration"
    description: """
                 #{sinceNext} The platform-wide settings held in the platform store: a stored value replaces the files' value on every core; deleting it gives each core its local value back. See [Platform configuration](/customer-resources/platform-configuration/). Answers carry `Cache-Control: no-store`. The writes are recorded in the platform trail with the values before and after; the reads are not audited.
                 """
    sections: [
      id: "platform-config-list"
      type: "method"
      title: "List the platform configuration"
      http: "GET /system/admin/platform-config"
      description: """
                   Every key the platform store may hold in this release, with its value and where it comes from.

                   #{credential("config:read", false)}
                   """
      result:
        http: "200 OK"
        properties: [
          key: "rev"
          type: "number"
          description: """
                       The revision of the platform configuration, bumped by every change.
                       """
        ,
          key: "entries"
          type: "array of objects"
          description: """
                       Per key, sorted: `key`, `effective` (what this core reads), `source` (`platform-db` or `local`), `appliesAt` (`live` or `restart`), `sensitive`, `stepUp`, `capability`, `locked` (this core's lockdown refuses its writes); with a stored value also `value`, `updatedAt`, `updatedBy` (`{ kind: session | admin-key | setup | cli, userId?, coreId }`) and `localOverride` (`{ value }`, this core's own value the store hides).
                       """
        ,
          key: "coresBehind"
          type: "array of objects"
          description: """
                       `[{ coreId, rev }]`: the cores whose last reporting process has not loaded the latest revision (`rev`: the revision it loaded, or `null`).
                       """
        ]
    ,
      id: "platform-config-get"
      type: "method"
      title: "Get a platform configuration key"
      http: "GET /system/admin/platform-config/{key}"
      description: """
                   #{credential("config:read", false)}
                   """
      params:
        properties: [
          key: "key"
          type: "string"
          http:
            text: "set in request path"
          description: """
                       The dotted key, for example `service.name`.
                       """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "entry"
          type: "object"
          description: """
                       As an item of `entries` above.
                       """
        ]
      errors: [
        key: "unknown-resource"
        http: "404"
        description: """
                     Not a key the platform store may hold.
                     """
      ]
    ,
      id: "platform-config-set"
      type: "method"
      title: "Set a platform configuration key"
      http: "PUT /system/admin/platform-config/{key}"
      description: """
                   Writes the value for every core. The core that served the call reads it at once, the others within `platform.configPollSeconds` (15); a key with `appliesAt: restart` is read again at each core's next start.

                   #{credential("config:write", false)} For a key with `stepUp: true` (`service.eventTypes`, `service.assets.definitions`), a session needs a recent second factor ([step-up](#step-up)).
                   """
      params:
        properties: [
          key: "key"
          type: "string"
          http:
            text: "set in request path"
          description: """
                       The dotted key.
                       """
        ,
          key: "value"
          type: "any type"
          description: """
                       The value, checked against the key's schema.
                       """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "entry"
          type: "object"
          description: """
                       The key after the write.
                       """
        ,
          key: "appliesAt"
          type: "string"
          description: """
                       `live` or `restart`.
                       """
        ,
          key: "rev"
          type: "number"
          description: """
                       The new revision.
                       """
        ]
      errors: [
        key: "invalid-parameters-format"
        http: "400"
        description: """
                     The body is not `{ "value": ... }`, or the value does not match the key's schema (`data.errors`).
                     """
      ,
        key: "forbidden"
        http: "403"
        description: """
                     A session without a recent second factor (`data.stepUp: true`).
                     """
      ,
        key: "admin-lockdown-key"
        http: "403"
        description: """
                     This core's lockdown makes the key read-only (`admin-lockdown-capability` when its capability is locked).
                     """
      ,
        key: "unknown-resource"
        http: "404"
        description: """
                     Not a key the platform store may hold.
                     """
      ]
    ,
      id: "platform-config-delete"
      type: "method"
      title: "Delete a platform configuration key"
      http: "DELETE /system/admin/platform-config/{key}"
      description: """
                   Removes the stored value: each core reads its configuration files again. A key this release does not know (a row left by a newer release) can be deleted too, and is treated as needing a second factor.

                   #{credential("config:write", false)}
                   """
      params:
        properties: [
          key: "key"
          type: "string"
          http:
            text: "set in request path"
          description: """
                       The dotted key.
                       """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "key"
          type: "string"
          description: """
                       The key.
                       """
        ,
          key: "deleted"
          type: "boolean"
          description: """
                       `false` when no value was stored.
                       """
        ,
          key: "entry"
          type: "object"
          description: """
                       The key after the deletion (absent for a key this release does not know).
                       """
        ,
          key: "rev"
          type: "number"
          description: """
                       The revision.
                       """
        ]
      errors: [
        key: "forbidden"
        http: "403"
        description: """
                     A session without a recent second factor (`data.stepUp: true`).
                     """
      ,
        key: "admin-lockdown-key"
        http: "403"
        description: """
                     This core's lockdown makes the key read-only.
                     """
      ]
    ]
  ,
    id: "oauth-review"
    title: "OAuth app review"
    description: """
                 #{sinceNext} The review acts of `bin/oauth-client.js` and the decisions about app publishers, over HTTP. None asks for a second factor; none is break-glass. These permissions come only from grants at scope `platform` or `region:<r>`, and each route keeps to the rows the caller's grants cover by region: a row out of reach answers 404, as a missing one. See [OAuth control levels and app review](/customer-resources/oauth-app-review/#review-over-http). Answers carry `Cache-Control: no-store`, never a secret hash, and mask a capability URL's token. The acts are recorded in the platform trail, in the acting administrator's trail and in the client owner's or publisher's trail; the reads are not audited.
                 """
    sections: [
      id: "oauth-clients-list"
      type: "method"
      title: "List OAuth clients"
      http: "GET /system/admin/oauth/clients"
      description: """
                   #{credential("oauthClients:read", false)}
                   """
      params:
        properties: [
          key: "queue"
          type: "boolean"
          optional: true
          http:
            text: "query parameter"
          description: """
                       `true`: only the review queue (developer clients whose review does not stand, and clients under review), computed at each read.
                       """
        ,
          key: "origin"
          type: "string"
          optional: true
          http:
            text: "query parameter"
          description: """
                       `operator`, `metadata-document` or `developer`.
                       """
        ,
          key: "status"
          type: "string"
          optional: true
          http:
            text: "query parameter"
          description: """
                       `active`, `suspended` or `review`.
                       """
        ,
          key: "limit"
          type: "number"
          optional: true
          http:
            text: "query parameter"
          description: """
                       1 to 1000. Without `limit` and `skip`, every row.
                       """
        ,
          key: "skip"
          type: "number"
          optional: true
          http:
            text: "query parameter"
          description: """
                       Rows to skip.
                       """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "clients"
          type: "array of objects"
          description: """
                       One line per client: `clientId`, `kind`, `origin`, `owner`, `name`, `status`, `regions`, `updatedAt` and the review fields.
                       """
        ]
    ,
      id: "oauth-clients-get"
      type: "method"
      title: "Get an OAuth client"
      http: "GET /system/admin/oauth/clients/{clientId}"
      description: """
                   The client as `bin/oauth-client.js show` prints it.

                   #{credential("oauthClients:read", false)}
                   """
      result:
        http: "200 OK"
        properties: [
          key: "client"
          type: "object"
          description: """
                       The row, with `clientSecretHash: "(set)"` (never the hash), key sets by thumbprint, and its `statusLog`.
                       """
        ,
          key: "validation"
          type: "object"
          description: """
                       The block the consent screen gets: `level`, `publisher`, `validatedAt`.
                       """
        ,
          key: "digest"
          type: "string"
          description: """
                       The review digest of the row as it stands: what [Approve an OAuth client](#approve-an-oauth-client) takes.
                       """
        ,
          key: "reviewStands"
          type: "boolean"
          description: """
                       Whether the stored app review still matches the row.
                       """
        ,
          key: "inQueue"
          type: "boolean"
          description: """
                       Whether the client is in the review queue.
                       """
        ]
      errors: [
        key: "unknown-resource"
        http: "404"
        description: """
                     No such client, or out of the caller's reach.
                     """
      ]
    ,
      id: "oauth-clients-approve"
      type: "method"
      title: "Approve an OAuth client"
      http: "POST /system/admin/oauth/clients/{clientId}/approve"
      description: """
                   Validates the row as the reviewer read it. On a developer's client it records the app review; on a client under review it also approves the held changes (back to `active`); on a suspended one it approves the changes made meanwhile (it stays suspended). The answer does not give the new digest: read the client again.

                   #{credential("oauthClients:review", false)}
                   """
      params:
        properties: [
          key: "digest"
          type: "string"
          description: """
                       The client's current review digest, as read.
                       """
        ,
          key: "reason"
          type: "string"
          optional: true
          description: """
                       1 to 500 characters, given to the client's owner as written.
                       """
        ]
      result:
        http: "200 OK"
        description: """
                     The client as [Get an OAuth client](#get-an-oauth-client) answers it, with `changed`.
                     """
      errors: [
        key: "stale-resource"
        http: "409"
        description: """
                     The digest is not the current one: nothing was written.
                     """
      ,
        key: "invalid-operation"
        http: "400"
        description: """
                     Nothing to approve (an operator's or a metadata-document client with nothing held), or a row the registration rules now refuse (`invalid-row`).
                     """
      ,
        key: "unknown-resource"
        http: "404"
        description: """
                     No such client, or out of the caller's reach.
                     """
      ]
    ,
      id: "oauth-clients-unvalidate"
      type: "method"
      title: "Withdraw an app review"
      http: "POST /system/admin/oauth/clients/{clientId}/unvalidate"
      description: """
                   Withdraws a developer's client review: it is no longer App Validated.

                   #{credential("oauthClients:review", false)}
                   """
      params:
        properties: [
          key: "reason"
          type: "string"
          description: """
                       1 to 500 characters.
                       """
        ]
      result:
        http: "200 OK"
        description: """
                     The client, with `changed`.
                     """
    ,
      id: "oauth-clients-suspend"
      type: "method"
      title: "Suspend an OAuth client"
      http: "POST /system/admin/oauth/clients/{clientId}/suspend"
      description: """
                   Stops the client from being served (authorization, consent and refresh refused) until it is resumed.

                   #{credential("oauthClients:review", false)}
                   """
      params:
        properties: [
          key: "reason"
          type: "string"
          description: """
                       1 to 500 characters.
                       """
        ]
      result:
        http: "200 OK"
        description: """
                     The client, with `changed`.
                     """
    ,
      id: "oauth-clients-resume"
      type: "method"
      title: "Resume an OAuth client"
      http: "POST /system/admin/oauth/clients/{clientId}/resume"
      description: """
                   Serves a suspended client again. Refused for a client under review or holding unapproved changes: approve it first.

                   #{credential("oauthClients:review", false)}
                   """
      params:
        properties: [
          key: "reason"
          type: "string"
          optional: true
          description: """
                       1 to 500 characters.
                       """
        ]
      result:
        http: "200 OK"
        description: """
                     The client, with `changed`.
                     """
      errors: [
        key: "invalid-operation"
        http: "400"
        description: """
                     The client is under review or holds unapproved changes.
                     """
      ]
    ,
      id: "publishers-list"
      type: "method"
      title: "List publishers"
      http: "GET /system/admin/oauth/publishers"
      description: """
                   The publisher rows the caller's grants cover.

                   #{credential("publishers:read", false)}
                   """
      params:
        properties: [
          key: "status"
          type: "string"
          optional: true
          http:
            text: "query parameter"
          description: """
                       `none`, `pending`, `validated` or `suspended`.
                       """
        ,
          key: "limit"
          type: "number"
          optional: true
          http:
            text: "query parameter"
          description: """
                       1 to 1000.
                       """
        ,
          key: "skip"
          type: "number"
          optional: true
          http:
            text: "query parameter"
          description: """
                       Rows to skip.
                       """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "publishers"
          type: "array of objects"
          description: """
                       Per publisher: `userId`, `status`, `displayName`, `regions`, `updatedAt`.
                       """
        ]
    ,
      id: "publishers-get"
      type: "method"
      title: "Get a publisher"
      http: "GET /system/admin/oauth/publishers/{userId}"
      description: """
                   #{credential("publishers:read", false)}
                   """
      result:
        http: "200 OK"
        properties: [
          key: "publisher"
          type: "object"
          description: """
                       `userId`, `status`, `displayName`, `regions`, `updatedAt` and `statusLog` (the last 50 decisions: `{ at, by, from, to, reason }`).
                       """
        ]
      errors: [
        key: "unknown-resource"
        http: "404"
        description: """
                     No such publisher row, or out of the caller's reach.
                     """
      ]
    ,
      id: "publishers-set"
      type: "method"
      title: "Decide about a publisher"
      http: "PUT /system/admin/oauth/publishers/{userId}"
      description: """
                   Sets a publisher's status: `validated` makes its apps Publisher Validated, on every core, from their next consent offer or refresh. Creating a row (none stored yet) needs a grant at scope `platform`; a reviewer scoped to a region decides only the rows assigned to its region, and may only leave them in regions it covers.

                   #{credential("publishers:review", false)}
                   """
      params:
        properties: [
          key: "userId"
          type: "string"
          http:
            text: "set in request path"
          description: """
                       The publisher's account id.
                       """
        ,
          key: "status"
          type: "string"
          description: """
                       `none`, `pending`, `validated` or `suspended`.
                       """
        ,
          key: "displayName"
          type: "string"
          optional: true
          description: """
                       At most 128 characters, answered to consent screens once validated. Left out: kept; `null`: removed.
                       """
        ,
          key: "regions"
          type: "array of strings"
          optional: true
          description: """
                       The regions the publisher is assigned to. Left out: kept; `null`: removed.
                       """
        ,
          key: "reason"
          type: "string"
          description: """
                       1 to 500 characters, given to the publisher as written.
                       """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "publisher"
          type: "object"
          description: """
                       The row after the decision, with its `statusLog`.
                       """
        ]
      errors: [
        key: "invalid-parameters-format"
        http: "400"
        description: """
                     A malformed parameter, or `regions` outside the reviewer's reach.
                     """
      ,
        key: "unknown-resource"
        http: "404"
        description: """
                     Out of the caller's reach.
                     """
      ]
    ]
  ,
    id: "portal"
    title: "Portal"
    description: """
                 What the administration portal reads.
                 """
    sections: [
      id: "portal-settings"
      type: "method"
      title: "Get the portal settings"
      http: "GET /system/portal/settings"
      description: """
                   #{sinceNext} What the portal shows on this platform, from `portal.*`. No credential, nothing secret. A call with an `Origin` follows the origin rule.
                   """
      result:
        http: "200 OK"
        properties: [
          key: "contract"
          type: "number"
          description: """
                       The portal contract this core implements.
                       """
        ,
          key: "spaces"
          type: "array of strings"
          description: """
                       `portal.spaces` (default `admin`, `developer`).
                       """
        ,
          key: "modules"
          type: "object"
          description: """
                       `disabled` and `order`: module ids from `portal.modules.disabled` and `portal.modules.order`.
                       """
        ]
    ,
      id: "portal-context"
      type: "method"
      title: "Get the portal context"
      http: "GET /system/admin/portal/context"
      description: """
                   #{sinceSetup} What the caller may do on the core that answers. Not audited; answered with `Cache-Control: no-store`.

                   **Credential:** any administrator subject: the admin key (also under `break-glass`), an administrator session, or a setup session.
                   """
      result:
        http: "200 OK"
        properties: [
          key: "portalContext"
          type: "object"
          description: """
                       `core` (`id`, `url` with a trailing slash, an empty string when the core knows no address), `setup` (`state`), `subject` (`kind`: `key`, `session` or `setup`; `userId`, `permissions`, `denied`), `capabilities` (the capabilities this core offers, without those its lockdown hides), `portal` (`url`, `setupPageUrl`), `adminSession` (`ttlMinutes`, `stepUpMinutes`, `mfaRequired`), and when they say something, `lockdown` (`capabilities`: `{ <capability>: readonly | hidden }`, `platformConfig.readonly`) and `localPolicy`.
                       """
        ]
    ]
  ,
    id: "cores"
    title: "Cluster and cores"
    sections: [
      id: "list-cores"
      type: "method"
      title: "List cores"
      http: "GET /system/admin/cores"
      description: """
                   Lists the cluster's cores with a per-core user count.

                   #{credential("cores:read", true)}
                   """
      result:
        http: "200 OK"
        properties: [
          key: "cores"
          type: "array of objects"
          description: """
                       One entry per core: `id`, `url`, `hosting` (or null), `available` (boolean), `userCount`.
                       """
        ]
    ,
      id: "ack-core"
      type: "method"
      title: "Acknowledge a core (bootstrap)"
      http: "POST /system/admin/cores/ack"
      description: """
                   Called by a freshly bootstrapped core to acknowledge joining the cluster. Flips the core to `available: true` and returns a cluster snapshot. **Authenticated by a one-time join token in the request body**, not the admin key. Operators normally trigger this indirectly via `bin/bootstrap.js`.
                   """
      result:
        http: "200 OK"
        description: """
                     Cluster snapshot from the bootstrap handler.
                     """
    ]
  ,
    id: "certificates"
    title: "TLS certificates"
    sections: [
      id: "list-certs"
      type: "method"
      title: "List certificates"
      http: "GET /system/admin/certs"
      description: """
                   Lists TLS certificate metadata. Never returns certificate or key material.

                   #{credential("certs:read", false)}
                   """
      result:
        http: "200 OK"
        properties: [
          key: "certs"
          type: "array of objects"
          description: """
                       One entry per certificate: `hostname`, `issuedAt`, `expiresAt`, `daysUntilExpiry` (integer or null).
                       """
        ]
    ,
      id: "force-renew"
      type: "method"
      title: "Force certificate renewal"
      http: "POST /system/admin/certs/force-renew"
      description: """
                   Triggers an operator-initiated ACME certificate rollover on the renewer core.

                   #{credential("certs:write", false)}
                   """
      params:
        properties: [
          key: "hostname"
          type: "string"
          optional: true
          description: """
                       The host to renew; defaults to the core's primary host.
                       """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "ok"
          type: "boolean"
        ,
          key: "hostname"
          type: "string"
        ,
          key: "issuedAt"
          type: "timestamp"
        ,
          key: "expiresAt"
          type: "timestamp"
        ]
      errors: [
        key: "invalid-request"
        http: "400"
        description: """
                     `hostname` must be a string when provided.
                     """
      ,
        key: "renewal-failed"
        http: "400"
        description: """
                     `{ ok: false, error }` when this core is not the renewer, Let's Encrypt is disabled, or ACME fails.
                     """
      ]
    ]
  ,
    id: "users"
    title: "Users"
    description: """
                 Since an administrator session may hold its permission through a grant covering this core only, these routes keep to this core for a session (from the release after 2.0.0-rc.91): see each one. The admin key keeps the platform-wide behaviour.
                 """
    sections: [
      id: "list-users"
      type: "method"
      title: "List users"
      http: "GET /system/admin/users"
      description: """
                   Lists the users. Without `limit`, `skip` and `search`, every user, in the index's order.

                   #{credential("users:read", false)}
                   """
      params:
        properties: [
          key: "limit"
          type: "number"
          optional: true
          http:
            text: "query parameter"
          description: """
                       From the release after 2.0.0-rc.91: page size, 1 to 1000.
                       """
        ,
          key: "skip"
          type: "number"
          optional: true
          http:
            text: "query parameter"
          description: """
                       From the release after 2.0.0-rc.91: users to skip.
                       """
        ,
          key: "search"
          type: "string"
          optional: true
          http:
            text: "query parameter"
          description: """
                       From the release after 2.0.0-rc.91: a username prefix, at most 64 characters.
                       """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "users"
          type: "array of objects"
          description: """
                       Per user: `username`, `id`, `email`, `language`, and `core` (only on multi-core).
                       """
        ,
          key: "total"
          type: "number"
          description: """
                       With `limit`, `skip` or `search`: the users matching `search` (all without it), before `skip` and `limit`.
                       """
        ]
    ,
      id: "create-user"
      type: "method"
      title: "Create user"
      http: "POST /system/create-user"
      description: """
                   Registers a new user.

                   #{credential("users:write", false)}
                   """
      params:
        properties: [
          key: "username"
          type: "string"
        ,
          key: "password"
          type: "string"
        ,
          key: "email"
          type: "string"
        ,
          key: "appId"
          type: "string"
        ]
      result:
        http: "201 Created"
        properties: [
          key: "id"
          type: "string"
          description: """
                       The new user id.
                       """
        ]
    ,
      id: "user-info"
      type: "method"
      title: "Get user info"
      http: "GET /system/user-info/{username}"
      description: """
                   Per-user usage statistics and storage. From the release after 2.0.0-rc.91 recorded in the platform trail and in the read account's own trail (`account.readByAdmin`).

                   #{credential("users:read", false)}
                   """
      params:
        properties: [
          key: "username"
          type: "string"
        ]
      result:
        http: "200 OK"
        properties: [
          key: "userInfo"
          type: "object"
          description: """
                       `username`, `storageUsed`, `lastAccess`, `callsTotal`, `callsDetail`, `callsPerAccess`.
                       """
        ]
      errors: [
        key: "unknown-resource"
        http: "404"
        description: """
                     Unknown user.
                     """
      ]
    ,
      id: "deactivate-mfa"
      type: "method"
      title: "Deactivate a user's MFA"
      http: "DELETE /system/users/{username}/mfa"
      description: """
                   Clears the user's multi-factor authentication.

                   #{credential("users:resetMfa", false)}
                   """
      params:
        properties: [
          key: "username"
          type: "string"
        ]
      result:
        http: "204 No Content"
    ,
      id: "update-user"
      type: "method"
      title: "Update user platform fields"
      http: "PUT /system/users"
      description: """
                   Updates a user's indexed / unique platform fields. The username cannot be changed. With an administrator session, a username with no account on this core answers 404.

                   #{credential("users:write", false)}
                   """
      params:
        properties: [
          key: "username"
          type: "string"
        ,
          key: "user"
          type: "object"
          description: """
                       Fields to set.
                       """
        ,
          key: "fieldsToDelete"
          type: "object"
          optional: true
        ]
      result:
        http: "200 OK"
        properties: [
          key: "user"
          type: "boolean"
        ]
    ,
      id: "validate-user"
      type: "method"
      title: "Reserve a user (pre-registration)"
      http: "POST /system/users/validate"
      description: """
                   Reserves a username and unique fields ahead of registration, verifying an invitation token. With an administrator session, a `core` other than this one is refused before anything is reserved.

                   #{credential("users:write", false)}
                   """
      params:
        properties: [
          key: "username"
          type: "string"
        ,
          key: "invitationToken"
          type: "string"
        ,
          key: "uniqueFields"
          type: "object"
          optional: true
        ,
          key: "core"
          type: "string"
          optional: true
        ]
      result:
        http: "200 OK"
        properties: [
          key: "reservation"
          type: "boolean"
        ]
      errors: [
        key: "reservation-refused"
        http: "400"
        description: """
                     `{ reservation: false, error }` with id `invalid-parameters-format` (no username, or a username account creation would refuse: 5 to 60 lowercase letters, digits or dashes, starting and ending with a letter or digit; nothing is reserved), `invitationToken-invalid` or `item-already-exists`.
                     """
      ]
    ,
      id: "registry-delete"
      type: "method"
      title: "Delete a user's platform fields"
      http: "DELETE /system/users/{username}"
      description: """
                   Deletes only the platform-side unique / indexed fields for a user (NOT their stored data).

                   #{credential("users:delete", false)} #{stepUp}
                   """
      params:
        properties: [
          key: "username"
          type: "string"
        ,
          key: "onlyReg"
          type: "boolean"
          description: """
                       Required (`?onlyReg=true`); this route never touches base storage.
                       """
        ,
          key: "dryRun"
          type: "boolean"
          optional: true
        ]
      result:
        http: "200 OK"
        properties: [
          key: "result"
          type: "object"
          description: """
                       `dryRun`, `deleted`.
                       """
        ]
      errors: [
        key: "invalid-operation"
        http: "400"
        description: """
                     Missing `onlyReg=true`.
                     """
      ,
        key: "unknown-resource"
        http: "404"
        description: """
                     Unknown user.
                     """
      ]
    ,
      id: "full-delete"
      type: "method"
      title: "Delete a user (full)"
      http: "DELETE /users/{username}"
      description: """
                   Full cascading delete of a user on their home core: base storage, attachments, high-frequency series, audit, sessions, platform and index entries. Served on the user's core (not under `/system`). Accepts either the admin key or the user's own personal token in the `Authorization` header (when `user-account.delete` includes `adminToken`, the default). Under `auth.adminAccessKeyScope: break-glass` the admin key no longer deletes accounts; a core's lockdown of `users` refuses an admin-key deletion. The holder of the platform's last lasting owner grant cannot delete that account with its own token (`400 invalid-operation`, `data.id: last-owner`).
                   """
      params:
        properties: [
          key: "username"
          type: "string"
        ]
      result:
        http: "200 OK"
    ,
      id: "get-access"
      type: "method"
      title: "Resolve an access"
      http: "GET /system/accesses/{accessId}"
      description: """
                   Resolves an access id to its owning user and metadata (used for breach scoping). With an administrator session on a multi-core platform, an access of another core's account answers 404.

                   #{credential("users:read", false)}
                   """
      params:
        properties: [
          key: "accessId"
          type: "string"
        ]
      result:
        http: "200 OK"
        properties: [
          key: "accessIndex"
          type: "object"
          description: """
                       Owning user and access metadata; includes `deleted` for deleted accesses.
                       """
        ]
      errors: [
        key: "unknown-resource"
        http: "404"
        description: """
                     Access not found.
                     """
      ]
    ]
  ,
    id: "mail-templates"
    title: "Mail templates"
    description: """
                 Manage the in-core email templates stored in the platform database. The CLI complement is `bin/mail.js`.
                 """
    sections: [
      id: "list-templates"
      type: "method"
      title: "List templates"
      http: "GET /system/admin/mail/templates"
      description: """
                   #{credential("mail:read", false)}
                   """
      result:
        http: "200 OK"
        properties: [
          key: "templates"
          type: "array of objects"
          description: """
                       `type`, `lang`, `part`, `length`.
                       """
        ]
    ,
      id: "get-template"
      type: "method"
      title: "Get a template"
      http: "GET /system/admin/mail/templates/{type}/{lang}/{part}"
      description: """
                   Returns the raw Pug of one template as `text/plain`.

                   #{credential("mail:read", false)}
                   """
      result:
        http: "200 OK"
      errors: [
        key: "unknown-resource"
        http: "404"
        description: """
                     Unknown template.
                     """
      ]
    ,
      id: "put-template"
      type: "method"
      title: "Upsert a template"
      http: "PUT /system/admin/mail/templates/{type}/{lang}/{part}"
      description: """
                   Creates or replaces a template.

                   #{credential("mail:write", false)}
                   """
      params:
        properties: [
          key: "pug"
          type: "string"
          description: """
                       The template source.
                       """
        ]
      result:
        http: "204 No Content"
      errors: [
        key: "invalid-request-structure"
        http: "400"
        description: """
                     Body must be `{ pug }`.
                     """
      ]
    ,
      id: "delete-template"
      type: "method"
      title: "Delete a template"
      http: "DELETE /system/admin/mail/templates/{type}/{lang}/{part}"
      description: """
                   #{credential("mail:write", false)}
                   """
      result:
        http: "204 No Content"
    ,
      id: "send-test"
      type: "method"
      title: "Send a test mail"
      http: "POST /system/admin/mail/send-test"
      description: """
                   Sends a test email using a template. Requires SMTP to be configured.

                   #{credential("mail:write", false)}
                   """
      params:
        properties: [
          key: "type"
          type: "string"
        ,
          key: "lang"
          type: "string"
        ,
          key: "recipient"
          type: "string | object"
          description: """
                       An email string, or `{ name, email }`.
                       """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "sent"
          type: "boolean"
        ]
    ]
  ,
    id: "integrity"
    title: "Integrity"
    sections: [
      id: "check-platform-integrity"
      type: "method"
      title: "Check platform integrity"
      http: "GET /system/check-platform-integrity"
      description: """
                   Runs the platform and user-index integrity checks.

                   #{credential("integrity:read", true)}
                   """
      result:
        http: "200 OK"
        properties: [
          key: "checks"
          type: "array"
          description: """
                       The platform and users-index check results.
                       """
        ]
    ,
      id: "migrations-status"
      type: "method"
      title: "Storage migrations status"
      http: "GET /system/migrations-status"
      description: """
                   Whether the storage schema is behind the code, for deploy checks. With `migrations.autoRunOnStart: false` a core boots and serves with migrations pending, and the methods that need the new schema fail until `node bin/migrate.js up` has run: poll this route until `upToDate` is `true` before switching traffic. The state is read on every call. Answers 200 whenever the state could be read, pending or not; a 404 means no or a wrong credential, or a core older than this route.

                   #{credential("migrations:read", true)}
                   """
      result:
        http: "200 OK"
        properties: [
          key: "migrations"
          type: "object"
          description: """
                       `autoRunOnStart` (boolean), `upToDate` (boolean), `pending` (number of migrations not applied, all engines), `engines`: per migration-capable engine `{ id, currentVersion, targetVersion, pending }` (`pending`: the migration filenames not applied yet). With `autoRunOnStart: true`, `upToDate: false` means the boot-time run failed or was interrupted.
                       """
        ]
    ,
      id: "event-types-status"
      type: "method"
      title: "Event-types dictionary status"
      http: "GET /system/event-types-status"
      description: """
                   Whether the published event-types dictionary has loaded. While it has never loaded the core runs `degraded` on its embedded dictionary and refuses unknown event types: alert on `degraded: true`. From the release after 2.0.0-rc.91, `lastError` of a failed download gives the HTTP status class only (`HTTP 4xx`).

                   #{credential("observability:read", true)}
                   """
      result:
        http: "200 OK"
        properties: [
          key: "eventTypes"
          type: "object"
          description: """
                       `degraded`, `everSucceeded`, `source`, `version`, `embeddedVersion`, `lastSuccessAt`, `lastAttemptAt`, `lastError`.
                       """
        ]
    ,
      id: "audit-status"
      type: "method"
      title: "Audit status"
      http: "GET /system/audit-status"
      description: """
                   From 2.0.0-rc.90. How many audit records the answering core could not write since it started: alert on `lost.total` above 0. Counts only, with no account, method or message; the core's `error` log lines carry the failures. Each core answers for itself, so poll every core. See [audit setup](/customer-resources/audit-setup/#records-that-could-not-be-written).

                   #{credential("observability:read", true)}
                   """
      result:
        http: "200 OK"
        properties: [
          key: "audit"
          type: "object"
          description: """
                       `active` (boolean, `audit.active`), `scope` (`core`: all the workers of the core; `process`: only the process that answered, when it runs without a master or the master did not answer in time: a partial answer on a core with several workers), `since` (when the counting process started, in seconds), `lost`: `total`, `byKind` (`valid`, `error`, `event`), `byReason` (`storage-write-failed`, `storage-unavailable`, `invalid-record`, `syslog-failed`), `lastAt` (time of the last one in seconds, or `null`).
                       """
        ]
    ]
  ,
    id: "operator-clis"
    title: "Operator CLIs"
    description: """
                 The `bin/*.js` scripts complement the HTTP surface (they open the storages / platform database directly, so they work while the API is down). Key ones:

                 - **admin.js**: setup and administrators: `setup-code`, `setup finish`, `claim-code`, `roles list|grant|revoke`, `sessions revoke`, `audit tail`. See [First boot and administrators](/customer-resources/administrators/#binadminjs).
                 - **platform-config.js**: the platform configuration held in the platform store: `list`, `get`, `set`, `unset`, `seed`, `export`, `import`. See [Platform configuration](/customer-resources/platform-configuration/#editing-from-a-cores-shell-binplatform-configjs).
                 - **bootstrap.js**: cluster bootstrap: `new-core`, `init-ca-holder`, `list-tokens`, `revoke-token`, `promote-core`.
                 - **dns-records.js**: manage persistent DNS records: `list`, `load`, `delete`, `export`.
                 - **observability.js**: OpenTelemetry posture: `show`, `enable`, `disable`, `set-endpoint`, `set-header`, `set-interval`, `set-app-name`.
                 - **mail.js**: mail templates: `templates list|get|set|delete|seed`, `send-test`.
                 - **oauth-client.js**: OAuth2 app-account management: `create`, `list`, `show`, `update`, `revoke`, key revocation, and the review acts `validate`, `unvalidate`, `suspend`, `resume`.
                 - **backup.js** / **migrate.js** / **migrate-platform.js**: backup/restore and database/platform migrations.
                 - **integrity-check.js**, **backfill-access-index.js**, **breach-scope.js**, **reconcile-user-cores.js**: maintenance.
                 - **check-config.js**, **config-to-env.js**, **init.js**: configuration and install.

                 Run each with `--help` for its full options.
                 """
  ]
