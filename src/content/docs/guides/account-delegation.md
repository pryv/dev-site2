---
title: 'Account delegation'
description: How to use Pryv.io account delegation to let one account (a parent or guardian) fully control another (a child or dependent), including the create-from-delegate flow, the request-to-attach handshake, delegate tokens, and the genuine-login rule for removing a delegate.
---

**Account delegation** lets one Pryv.io account hold full control over another. It is the mechanism for parent- or guardian-controlled accounts: a parent manages a young child's account, or a caregiver manages the account of a dependent adult, using their own everyday login.

It complements the [Cross-account Messaging & Consent (CMC) guide](/guides/cross-account-messaging/), but the two solve different problems. CMC shares *selected, permission-bounded* data between two independent account owners, each of whom stays in control of their own account. Delegation grants *full, owner-equivalent* control of one account to another. Reach for delegation when one person is responsible for another person's account, not merely sharing data with them.

## Vocabulary

A **delegation relationship** is a directed link between exactly two accounts:

- The **controlled account** is the account being managed. This is the child, or the dependent adult.
- The **delegate** is the account holding control. This is the parent, or the caregiver.

The same account can sit on both sides of different relationships: a parent's account is a delegate of their child's account, while another caregiver may in turn be a delegate of the parent's own account.

Two phrasings describe a relationship from each side:

| Phrasing | Point of view | Means |
| --- | --- | --- |
| "the accounts I **manage**" / "my **controlled accounts**" | the delegate | the accounts this account controls |
| "**my delegates**" / "the accounts my account is **delegated to**" | the controlled account | the accounts that control this one |

A relationship has one of two states:

- **`invite`** — the controlled account has requested a delegate, and the delegate has not yet accepted.
- **`active`** — the delegate has accepted, or the account was created directly by a delegate (active immediately).

There is no resting "detached" state: removing a delegate deletes the relationship. The full history lives in the audit trail.

An account can have **several delegates at once** (for example both parents of a child). Each relationship is fully independent: removing one delegate leaves the others untouched.

## The trust model — what a delegate can do

A delegate holds an **owner-equivalent** token over the controlled account. There is exactly one thing it cannot do: remove a delegation relationship. Everything else an account owner can do, a delegate can do.

> **A delegate has full control of the controlled account.** A delegate can read and change all of its data; manage its streams and accesses; change its password, email and MFA; delete the account entirely; and add further delegates. Because a delegate can set the account's password, a delegate can also log in to the account directly, which includes the power to remove other delegates. Removing any delegate requires logging in to the controlled account itself. Every credential change, login, and removal is recorded in the account's audit trail.

This model is deliberate. The primary use case is a trusted parent or guardian who is responsible for an account they created. Two consequences follow and should be surfaced to users at the moment they grant delegation:

- **A delegate who holds the account's credentials controls the account outright.** A malicious delegate can change the password and MFA, locking the genuine owner out, and can log in as the account to remove other delegates. Delegation is a full trust relationship, not a limited grant.
- **The adult-to-adult case deserves the loudest warning.** A dependent adult delegating to a caregiver is trusting that caregiver at password-custody level. That includes the power to log in as them and to remove other delegates.

The protection that always holds is **attribution**: every action a delegate performs on the controlled account, including credential changes, added delegates, token issuance, and deletions, is recorded in the controlled account's audit trail and attributed to that specific delegate (see [Auditing](#auditing)).

There is no scoped or read-only delegate in this version. If you need permission-bounded sharing rather than full control, use [CMC](/guides/cross-account-messaging/) instead.

## Creating a controlled account from a delegate

A delegate can create a brand-new controlled account in one call. The relationship is `active` immediately, with no handshake and no consent step, because the account is created by, and for, the delegate.

```js
const res = await parentConn.api([{ method: 'delegations.createAccount', params: {
  username: 'kim-doe',
  email: null,        // optional
  password: null,     // optional
  core: null,         // optional target core on a multi-core platform
  language: 'en'
}}]);
// res[0].delegation = { relId, controlled: { username, hostSlug }, status: 'active', activatedAt }
```

Both `email` and `password` are optional:

- **Without an email**, the account simply has no email on file.
- **Without a password**, the account is created with an unguessable random password and cannot be logged into directly. It is reachable **only** through its delegates.

An account with no usable password is exactly what a parent wants for a young child: there is no login for the child to lose or leak, and the parent operates it entirely through delegation. The way *out* of that state is the [majority handover](#majority-handover), where a delegate sets a real password (or an email plus a password reset), the account owner logs in for the first time, and can then take over.

On a multi-core platform, `core` selects which core hosts the new account (it defaults to the delegate's own core). On a single-core platform, omit it.

## Requesting a delegate — the attach handshake

For an account that already exists and has its own credentials (the dependent-adult case), delegation is always **initiated by the controlled account**. There is no way for one account to unilaterally take control of another: the account being controlled must ask first, and the delegate must accept.

**1. The controlled account requests a delegate.**

```js
const res = await principalConn.api([{ method: 'delegations.requestAttach', params: {
  delegateUsername: 'carla-care'
}}]);
// res[0].delegation = { relId, delegate: { username }, status: 'invite', requestedAt, expiresAt }
```

This creates a pending invite. On a multi-core platform, the request is delivered to the delegate's core automatically. The invite carries an expiry (30 days by default).

**2. The delegate accepts (or refuses).**

```js
await caregiverConn.api([{ method: 'delegations.acceptAttach', params: {
  username: 'principal-pat'   // the controlled account's username
}}]);
// -> relationship becomes 'active'
```

or

```js
await caregiverConn.api([{ method: 'delegations.refuseAttach', params: {
  username: 'principal-pat'
}}]);
```

Refusing is the delegate's unilateral decline of a pending invite; it is not a detach and is always available to the delegate.

**3. Either side can list its relationships.**

```js
// The controlled account sees who controls it:
await principalConn.api([{ method: 'delegations.listDelegates' }]);
// { delegates: [ { relId, delegate: { username, hostSlug }, status, requestedAt, activatedAt, lastTokenIssuedAt } ] }

// The delegate sees the accounts it manages:
await caregiverConn.api([{ method: 'delegations.listControlled' }]);
// { controlled: [ { relId, controlled: { username, hostSlug }, status, requestedAt, activatedAt } ] }
```

A pending invite can be withdrawn by the controlled account with `delegations.cancelInvite` (this is subject to the same genuine-login rule as detach, below).

## Acting as a controlled account

To operate a controlled account, a delegate mints a **delegate token** on demand:

```js
const res = await parentConn.api([{ method: 'delegations.getToken', params: {
  username: 'kim-doe'
}}]);
const { token, apiEndpoint } = res[0];

// The delegate now talks to the controlled account's core directly:
const kidConn = new pryv.Connection(apiEndpoint /* with token */);
await kidConn.api([{ method: 'events.get', params: { limit: 20 } }]);
```

The delegate token is a **personal-class token**: it can do everything the account owner could do. It is minted freshly each time and follows the same lifetime as a normal login session; calling `getToken` again re-issues it. The control channel that authorizes minting never leaves the delegate's core; only the delegate token and the controlled account's endpoint are returned to the client.

When a delegate token calls [`access-info`](/reference/#access-info), the result carries an additive `delegation` field so the client knows it is operating a delegated account (see [Recognising a delegated token](#recognising-a-delegated-token)).

The delegate token is meant for the delegate's own, trusted apps (such as the platform's account app). A third-party app never receives it: to let such an app work on a controlled account, the delegate grants it an ordinary app access on that account, as described next.

## Granting an app access for a controlled account

A parent who signs in to an app may want the app to work on their child's account rather than on their own. The standard [auth request](/reference/#auth-request) supports this: after sign-in, the platform's authentication page asks **who the access is for**, and the app receives an app access on the account the parent picked.

**The flow:**

1. The app sends its auth request as usual and opens the returned `authUrl`.
2. The user (the delegate) signs in with their own credentials.
3. If the platform runs delegation (`features.delegation: true` in the [service information](/reference/#service-info)), the app did not opt out (see `actAs` below), and the user controls at least one `active` account, the page asks: this account, or one of the accounts it controls.
4. When the user picks a controlled account, the page obtains a [delegate token](#acting-as-a-controlled-account) for it, keeps it in memory only, and uses it on the controlled account's own core to check for and create the app access with the requested permissions (the same `deviceName`, `expireAfter`, `token` and `clientData` the app asked for). The delegate token is dropped once the access is handed over; it is never stored and never sent to the app.
5. The page accepts the request. The app's poll returns `ACCEPTED` with the **controlled account's** `username` and `apiEndpoint`, a token for that account, and a `delegation` block describing who granted it:

```json
{
  "status": "ACCEPTED",
  "username": "kim-doe",
  "apiEndpoint": "https://…@kim-doe.example.com/",
  "token": "…",
  "delegation": {
    "isDelegatedAccess": true,
    "controlledUsername": "kim-doe",
    "delegate": { "username": "parent-doe" }
  }
}
```

The `delegation` block of the poll is a **display hint** written by the authentication page (the platform's page does not include `delegate.hostSlug`). Base any decision on the token itself: [`access-info`](/reference/#access-info) called with it returns `delegation` with `grantedVia: 'app'` (see [Recognising a delegated token](#recognising-a-delegated-token)).

With lib-js, the app reads it after connecting:

```js
const service = await pryv.Browser.setupAuth({
  spanButtonID: 'pryv-button',
  authRequest: {
    requestingAppId: 'kid-health',
    requestedPermissions: [{ streamId: 'health', defaultName: 'Health', level: 'contribute' }]
    // actAs: 'deny'   // uncomment to keep the access on the signed-in account
  },
  onStateChange: async (state) => {
    if (state.status === 'ACCEPTED' && state.key != null) {
      const conn = await pryv.connectFromKey(state.key, serviceInfoUrl);
      const info = await conn.accessInfo();
      const actingFor = info.delegation?.grantedVia === 'app' ? info.user.username : null;
      // actingFor: the controlled account, when a delegate granted this access for it
    }
  }
}, serviceInfoUrl);
```

### Choosing whether to offer it: `actAs`

The auth request accepts an optional `actAs` field:

| Value | Effect |
| --- | --- |
| `'allow'` (also the behaviour when omitted) | The page may offer the accounts the user controls. |
| `'deny'` | The access is always for the signed-in account; the page does not ask. |
| a username | That controlled account is preselected; the user can still pick another one. An account the user does not control is simply not preselected. |

Any other value fails the auth request with `400 invalid-parameters`. A core that does not support `actAs` ignores it. Set `'deny'` when your app cannot work on an account other than the signed-in user's.

**Fixed tokens.** If the auth request carries a fixed `token`, the page applies it on whichever account the user picks. An app that uses a fixed token and lets the user switch between accounts therefore holds the same token value on several accounts. That is allowed (a token value only has to be unique within one account), but it is your app's design choice; use `actAs: 'deny'` if it does not suit you.

### What the controlled account sees

The access lives on the controlled account, like any app access its owner could have granted:

- The account's owner (for example a teenager who has taken over their account) sees it among the account's apps and can **revoke** it; the delegate and the app itself can revoke or update it too.
- The server marks it as granted through the delegation. This marker cannot be set, changed or removed by any client, and it is kept when the access is updated. Accesses the app creates with it (shared accesses) carry the same marker.
- Everything the app does on the account is recorded in the account's audit trail under the app's access, with the delegate named on the record (see [Auditing](#auditing)).
- If the account's owner later signs in to the same app on the same device, the existing access is reused, and it still ends with the delegation (below).

### When the delegate is removed

**Removing the delegate revokes what it granted.** [`delegations.detachDelegate`](#remove-a-delegate) deletes, together with the delegate token, every access granted through that delegation: the app accesses the delegate granted and the accesses those apps created. The app's token stops working on its next request. Accesses the account's owner granted are untouched; the owner can grant the app again from their own login.

### Grants a delegate cannot make

Some grant paths write accesses outside `accesses.create` and cannot yet record that they came through a delegation, so those grants would outlive it. A delegate token, and any access granted through a delegation, is refused on them; only the account's owner, signed in genuinely, can make these grants:

| Path | Refusal |
| --- | --- |
| OAuth2 consent (`POST /oauth2/authorize/accept`) | `403` with `error: 'access_denied'` |
| Writing a `consent/accept-cmc`, `consent/scope-update-cmc` or `consent/request-cmc` event ([CMC](/guides/cross-account-messaging/)) | `400 invalid-operation` with `error.data.id === 'delegation-grant-requires-owner'` |

## Removing a delegate — the genuine-login rule

Every power a delegation grants lives in tokens stored **on the controlled account**. Removing them there is the authoritative teardown, and it is the controlled account's exclusive right.

> **Removing a delegate requires a genuine login on the controlled account.** The request must be authenticated by a token that came from the controlled account's own login flow (its password, plus MFA if configured). A delegate token cannot remove a delegation, not another delegate's and not its own.

```js
// Authenticated as a genuine login on the controlled account:
await controlledConn.api([{ method: 'delegations.detachDelegate', params: {
  username: 'carla-care'
}}]);
```

Attempting this with a delegate token is rejected with `delegation-genuine-login-required` (403).

A detach immediately and permanently destroys the delegate's token and control channel on the controlled account, so the delegate loses access on its very next request, regardless of network reachability between cores. It also deletes every access granted through the delegation (see [When the delegate is removed](#when-the-delegate-is-removed)). Delegation resources cannot be deleted through the generic `accesses.*` or `events.*` APIs by any token, so this rule cannot be side-stepped. (Accesses granted *through* a delegation are not delegation resources: they are ordinary accesses that anyone entitled to revoke an access may revoke.)

There is deliberately **no delegate-initiated detach** in this version: a delegate cannot walk away on its own. A parent who created a passwordless child account must not be able to abandon it and strand it with no way in. The way a delegate is released is always through the controlled account logging in genuinely, as in the handover below.

> **The exact boundary.** The rule proves the *token* came from the controlled account's login flow; it does not prove *who* performed the login. A delegate that holds the account's credentials can set its password, log in as the account, obtain a genuine-login token, and use it to remove other delegates. This is a direct consequence of the owner-equivalent trust model, not a gap. Each such step (the password change, the login, the removal) is recorded and attributed in the audit trail.

## Worked walkthroughs

### Parent and child

1. **Create.** A parent creates the child's account from their own account with `delegations.createAccount` (no email, no password). It is `active` immediately.
2. **Operate.** The parent calls `delegations.getToken` whenever they need to act as the child, and manages the child's data with the returned token.
3. **Add the other parent.** From a delegate token acting as the child, the parent calls `delegations.requestAttach` naming the other parent, who accepts with `delegations.acceptAttach`. The child now has two independent delegates.

### Dependent adult and caregiver

1. **Request.** The dependent adult, logged into their own account, calls `delegations.requestAttach` naming the caregiver.
2. **Accept.** The caregiver accepts with `delegations.acceptAttach`. Before accepting, they should be shown the [trust-model warning](#the-trust-model--what-a-delegate-can-do): accepting means holding full, password-level control of the other person's account.
3. **Operate.** The caregiver uses `delegations.getToken` to act on the dependent adult's account.
4. **Release.** To remove the caregiver, the dependent adult logs into their **own** account and calls `delegations.detachDelegate`. A caregiver cannot remove itself.

### Majority handover

When a child reaches an age where they should own their account, or any owner takes over a delegate-run account, no new mechanism is needed:

1. Using a delegate token, the parent either **sets a password** on the account directly and hands it over, or **sets the account's email** and triggers the standard password reset so the new owner receives it.
2. The new owner **logs in genuinely** with their own credentials, obtaining a real login token that carries no delegation marker.
3. Only now, from that genuine login, can they call `delegations.detachDelegate` and remove the parent (and any other delegate).

The genuine-login detach rule and the delegate's power to set credentials fit together to produce a clean handover, using nothing more than the password-reset flow that already exists.

## Cross-core, same platform

On a multi-core Pryv.io platform, the delegate and the controlled account can live on **different cores of the same platform**. The delegation methods handle the core-to-core delivery for you: creating an account on another core, delivering an attach invite to the delegate's core, minting a delegate token across cores, and propagating a detach. The account tokens themselves never move between cores; each core issues and holds its own.

Cross-*platform* delegation (accounts on two different Pryv.io platforms) is not supported. That is CMC's territory.

## Recognising a delegated token

Delegation surfaces additively on [`access-info`](/reference/#access-info); nothing about existing responses changes. When the calling token is a delegate token, the result gains:

```json
{
  "delegation": {
    "isDelegatedAccess": true,
    "controlledUsername": "kim-doe",
    "delegate": { "username": "parent-doe", "hostSlug": "example-core" }
  }
}
```

The token acts *as* the controlled account, so `access-info`'s `user.username` remains the controlled account. A client can read the `delegation` field to know it is operating on a delegated account, and to display which delegate is acting.

An app access [granted for a controlled account](#granting-an-app-access-for-a-controlled-account), and any access such an app creates, reports the same shape with `grantedVia: 'app'`:

```json
{
  "delegation": {
    "isDelegatedAccess": true,
    "controlledUsername": "kim-doe",
    "delegate": { "username": "parent-doe", "hostSlug": "example-core" },
    "grantedVia": "app"
  }
}
```

This field is the authoritative signal that an app is acting for a controlled account; the `delegation` block of the auth request's `ACCEPTED` poll is only a display hint.

## Auditing

Delegation is fully attributable:

- **Per-delegate attribution is automatic.** Each delegate holds its own distinct token on the controlled account, so every action lands under that token in the account's audit trail. A delegate's activity is never blended with the owner's or with another delegate's.
- **Delegate identity on the record.** Audit events produced by a delegate token, or by an access granted through the delegation, carry an additive `content.delegation = { delegateUsername, delegateHostSlug }`, so the acting delegate is legible directly on the record.
- **Lifecycle events are audited.** Requests, accepts, refusals, token issuances, account creation, and detaches each leave an audit record on the account they execute on.

## API reference

All methods below belong to the `delegations.*` family, under the `/delegations` path on a user's API endpoint. **Controlled account** methods run on the account being managed; **delegate** methods run on the controlling account. Error ids are namespaced `delegation-*`.

Two token requirements appear:

- **Personal token** — a standard personal (login) token. A delegate token counts as personal for every method except detach and invite-cancel.
- **Genuine login** — a personal token that came from the account's own login flow and carries no delegation marker. A delegate token is rejected.

The whole family can be switched off by an operator via the `delegation:active` configuration flag (enabled by default); when disabled, none of these methods are registered.

### Request a delegate

| | |
| ---- | --------------- |
| id | `delegations.requestAttach` |
| HTTP | `POST /delegations/attach-request` |
| side | controlled account |
| token | personal (delegate tokens included) |

Requests attachment of a delegate. Creates a pending `invite` relationship and delivers it to the delegate's core.

**Parameters**

| | |
| --- | --- |
| `delegateUsername` | string — the account to request as a delegate. |

**Result** `HTTP 201 Created`

```json
{ "delegation": { "relId": "…", "delegate": { "username": "carla-care" },
  "status": "invite", "requestedAt": 1789000000, "expiresAt": 1791592000 } }
```

**Errors**

| Status | Error id | |
| --- | --- | --- |
| 404 | `delegation-unknown-username` | The delegate username does not resolve to an account. |
| 400 | `delegation-self-not-allowed` | An account cannot delegate to itself. |
| 409 | `delegation-already-exists` | A pending or active relationship to this delegate already exists. |
| 503 | `delegation-delivery-failed` | The delegate's core could not be reached; the request leaves no trace. |
| 403 | `forbidden` | A non-personal (app or shared) token was used; a personal token is required. |

### Accept a delegate invite

| | |
| ---- | --------------- |
| id | `delegations.acceptAttach` |
| HTTP | `POST /delegations/controlled/{username}/accept` |
| side | delegate |
| token | personal (delegate tokens included) |

Accepts a pending invite, activating the relationship. `{username}` is the controlled account.

**Result** `HTTP 200 OK`

```json
{ "delegation": { "relId": "…", "controlled": { "username": "principal-pat", "hostSlug": "example-core" },
  "status": "active", "activatedAt": 1789000100 } }
```

**Errors**

| Status | Error id | |
| --- | --- | --- |
| 404 | `delegation-not-found` | No pending invite from this account. |
| 410 | `delegation-invite-expired` | The invite has expired. |
| 400 | `delegation-delegate-mismatch` | The invite was not addressed to this account. |
| 503 | `delegation-delivery-failed` | The controlled account's core could not be reached. |

### Refuse a delegate invite

| | |
| ---- | --------------- |
| id | `delegations.refuseAttach` |
| HTTP | `POST /delegations/controlled/{username}/refuse` |
| side | delegate |
| token | personal (delegate tokens included) |

Declines a pending invite. This is a handshake decline, not a detach, and is always available to the delegate. Result: `HTTP 200 OK`, empty body.

### Cancel a pending invite

| | |
| ---- | --------------- |
| id | `delegations.cancelInvite` |
| HTTP | `POST /delegations/delegates/{username}/cancel` |
| side | controlled account |
| token | **genuine login** |

Withdraws a pending invite the controlled account sent. Because it removes a relationship record, it requires a genuine login (a delegate token cannot cancel invites). Result: `HTTP 200 OK`, empty body.

**Errors**

| Status | Error id | |
| --- | --- | --- |
| 403 | `delegation-genuine-login-required` | Called with a delegated (or non-personal) token. |
| 404 | `delegation-not-found` | No pending invite for this delegate. |

### List my delegates

| | |
| ---- | --------------- |
| id | `delegations.listDelegates` |
| HTTP | `GET /delegations/delegates` |
| side | controlled account |
| token | personal (delegate tokens included) |

Lists the accounts that control this account. Token values, control endpoints, and capability URLs are never included.

**Result** `HTTP 200 OK`

```json
{ "delegates": [ { "relId": "…", "delegate": { "username": "carla-care", "hostSlug": "example-core" },
  "status": "active", "requestedAt": 1789000000, "activatedAt": 1789000100, "lastTokenIssuedAt": 1789000500 } ] }
```

### List accounts I manage

| | |
| ---- | --------------- |
| id | `delegations.listControlled` |
| HTTP | `GET /delegations/controlled` |
| side | delegate |
| token | personal (delegate tokens included) |

Lists the accounts this account controls. A row's `status` may be `invite`, `active`, or `stale` (a local marker meaning the relationship is no longer reachable on the controlled account; see [Dismiss](#dismiss-a-stale-managed-account)).

**Result** `HTTP 200 OK`

```json
{ "controlled": [ { "relId": "…", "controlled": { "username": "kim-doe", "hostSlug": "example-core" },
  "status": "active", "requestedAt": 1789000000, "activatedAt": 1789000100 } ] }
```

### Get a delegate token

| | |
| ---- | --------------- |
| id | `delegations.getToken` |
| HTTP | `POST /delegations/controlled/{username}/token` |
| side | delegate |
| token | personal (delegate tokens included) |

Mints a fresh delegate token for an active controlled account and returns it with the controlled account's API endpoint. The control channel stays server-side; only the token and endpoint reach the client.

**Result** `HTTP 200 OK`

```json
{ "token": "…", "apiEndpoint": "https://kim-doe.example.com/" }
```

**Errors**

| Status | Error id | |
| --- | --- | --- |
| 404 | `delegation-not-found` | No relationship with this account. |
| 410 | `delegation-not-active` | The relationship is no longer active on the controlled account (the local row is marked `stale`). |
| 503 | `delegation-delivery-failed` | The controlled account's core could not be reached. |

### Create a controlled account

| | |
| ---- | --------------- |
| id | `delegations.createAccount` |
| HTTP | `POST /delegations/controlled` |
| side | delegate |
| token | personal (delegate tokens included) |

Creates a brand-new account controlled by the caller. The relationship is `active` immediately.

**Parameters**

| | |
| --- | --- |
| `username` | string — the new account's username. |
| `email` | string (optional) — omit for an account with no email. |
| `password` | string (optional) — omit for an account reachable only through its delegates. |
| `core` | string (optional) — target core on a multi-core platform; defaults to the caller's own core. |
| `language` | string (optional) — the account's language. |

**Result** `HTTP 201 Created`

```json
{ "delegation": { "relId": "…", "controlled": { "username": "kim-doe", "hostSlug": "example-core" },
  "status": "active", "activatedAt": 1789000100 } }
```

**Errors**

| Status | Error id | |
| --- | --- | --- |
| 409 | `delegation-username-taken` | The requested username is already in use. |
| 400 | `delegation-unknown-core` | The requested target core is unknown to this platform. |
| 400 | `delegation-self-not-allowed` | The username matches the caller. |
| 502 | `delegation-creation-failed` | Account creation failed; any partial state is rolled back. |

### Remove a delegate

| | |
| ---- | --------------- |
| id | `delegations.detachDelegate` |
| HTTP | `DELETE /delegations/delegates/{username}` |
| side | controlled account |
| token | **genuine login** |

Removes a delegate, authoritatively and immediately, on the controlled account. Destroys the delegate's token and control channel so it loses access on its next request, and deletes every access granted through the delegation (the app accesses the delegate granted and the accesses those apps created). For a pending invite, this cancels it. Requires a genuine login. Result: `HTTP 200 OK`, empty body.

**Errors**

| Status | Error id | |
| --- | --- | --- |
| 403 | `delegation-genuine-login-required` | Called with a delegated (or non-personal) token. |
| 404 | `delegation-not-found` | No relationship with this delegate. |

### Dismiss a stale managed account

| | |
| ---- | --------------- |
| id | `delegations.dismissControlled` |
| HTTP | `DELETE /delegations/controlled/{username}` |
| side | delegate |
| token | personal (delegate tokens included) |

Removes a `stale` row from the delegate's local list. This is housekeeping only: it removes no authority and never touches the controlled account. It is **not** a detach. Only a `stale` row can be dismissed. Result: `HTTP 200 OK`, empty body.

**Errors**

| Status | Error id | |
| --- | --- | --- |
| 400 | `delegation-mirror-not-stale` | The row is not stale; only stale rows are dismissable. |
| 404 | `delegation-not-found` | No such row. |

### access-info additions

[`access-info`](/reference/#access-info) gains an additive `delegation` field when the calling token is a delegate token or a control token. For a delegate token:

```json
{ "delegation": { "isDelegatedAccess": true, "controlledUsername": "kim-doe",
  "delegate": { "username": "parent-doe", "hostSlug": "example-core" } } }
```

For an access granted through the delegation (an app access granted for the controlled account, or an access such an app created), the same shape plus `"grantedVia": "app"`.

The field is purely additive; existing `access-info` behaviour is unchanged, and `user.username` remains the controlled account.

### Audit additions

Audit events produced by a delegate token, a control token, or an access granted through the delegation carry an additive `content.delegation`:

```json
{ "content": { "delegation": { "delegateUsername": "parent-doe", "delegateHostSlug": "example-core" } } }
```

Per-delegate attribution is automatic because each delegate holds its own distinct token on the controlled account.

### Core-to-core methods

The remaining `delegations.*` methods (`issueToken`, `acceptResponse`, `refuseResponse`, `acceptComplete`, `notifyDetach`, under `/delegations/controlled-side/*`) are used **between cores** to carry out the handshake, token minting, and detach propagation. They authorize on internal, forge-protected delegation credentials rather than on a client token, and are not part of the client-facing surface. Applications never call them directly; the methods above orchestrate them for you.

## Further reading

- [Cross-account Messaging & Consent (CMC)](/guides/cross-account-messaging/) — permission-bounded data sharing between two independent account owners.
- [Consent implementation](/guides/consent/) — the classical single-account consent flow.
- [Audit logs](/guides/audit-logs/) — how account activity is recorded.
- [API reference](/reference/) — the complete method reference.
