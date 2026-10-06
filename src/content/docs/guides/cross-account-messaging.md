---
title: 'Cross-account Messaging & Consent (CMC)'
description: How to use CMC, Pryv.io's protocol for federated cross-account consent, chat and system notifications between two user accounts on any platform.
---


This guide describes how to use **CMC** — Pryv.io's built-in protocol for federated, cross-account consent, chat and system notifications. With CMC, two Pryv accounts (which may live on different platforms) can mutually issue and receive data-grants, exchange chat messages, and send system alerts — all on top of standard Pryv events / streams / accesses.

It complements the [Consent request guide](/guides/consent/), which covers the classical single-account consent flow (one app obtaining an access token on one user's account). CMC is what you reach for when consent flows BETWEEN two end-user accounts.

## When to use CMC

Use CMC when:

- Two **end-user accounts** need to share data (e.g. a patient grants their doctor read access to selected streams; a study collector receives data from N participants).
- The data flow is **bi-directional** — chat exchanges, system alerts back-and-forth — not just one-shot reads.
- You want **scope changes** (widening / narrowing the data-grant) to be a first-class user action with audit trail.
- The two accounts may be on **different Pryv.io platforms** (federated). The plugin handles the inter-platform HTTPS plumbing for you.

If your use-case is "one app authenticating to one user's account", stick with the standard [access-request flow](/reference/#authenticate-your-app).

## Concepts

A CMC interaction always involves **two parties**:

- **Requester** — the actor asking for consent (e.g. the doctor's app, a study collector, a research institution).
- **Accepter** — the data-owner whose account is being asked.

The handshake creates **two paired accesses**:

- A **data-grant** access on the accepter's account, issued to the requester. Carries the offer's permissions (e.g. `fertility:read`).
- A **back-channel** access on the requester's account, issued to the accepter. Carries delivery rights for chat and system messages flowing in the reverse direction.

Together these two accesses form a **CMC consent**. Either party may revoke at any time.

### Delegable data-grants (`shared` vs `app`)

By default the data-grant is a Pryv `shared` access, which **cannot** call the
`accesses.*` methods. If the approved requester needs to **re-delegate**
least-privilege, individually-named access to the services acting on its behalf
(e.g. an orchestrator that hands each downstream participant its own scoped,
audited access), the request can opt into an **`app`** data-grant by setting
`request.accessType: "app"` on the offer (default `"shared"`):

```jsonc
{ "type": "consent/request-cmc",
  "content": {
    "request": {
      "title": {"en": "…"}, "description": {"en": "…"}, "consent": {"en": "…"},
      "permissions": [ { "streamId": "body", "level": "manage" } ],
      "accessType": "app"       // default "shared" — "app" makes the grant delegable
    } } }
```

An `app` data-grant can `accesses.create` **sub-accesses whose permissions are a
subset of the grant**, so the requester can issue a distinct, named access per
downstream actor (writes attribute to that named access in the owner's audit
trail). A `shared` grant stays non-delegable. Requires open-pryv.io ≥
`2.0.0-rc.9`. With the `@pryv/cmc` helper, pass `accessType` to `createInvite`
(see [Lib-js helpers](#lib-js-helpers)).

## Streams reserved by the plugin

The plugin auto-provisions a small reserved namespace on every account on first CMC use:

```
:_cmc:                      reserved root
  :_cmc:inbox               one-shot lifecycle delivery (consent/* events from peers)
  :_cmc:apps                parent of user-creatable app scopes
    :_cmc:apps:<app-code>   user-creatable, one per app
      <user-defined paths>  e.g. :study-A, :campaign-2026
        :chats              auto-created at acceptance time
          :chats:<peer>     one chat thread per peer
        :collectors         auto-created at acceptance time
          :collectors:<peer> one system channel per peer
  :_cmc:_internal           plugin-internal hidden region (capability mint, retry queue)
```

Apps must NEVER write to `:_cmc:_internal:*`. They write to their own `:_cmc:apps:<app-code>:*` streams; the plugin handles everything inside `:_cmc:_internal:*` and `:_cmc:inbox`.

## Event types

CMC types follow the Pryv `<class>/<format>` convention. Implementation formats are suffixed with `-cmc` so the [data-types directory](/event-types/) groups CMC entries together within shared classes.

| Type | When you write it |
|---|---|
| `consent/request-cmc` | Requester writes to start a request. The plugin mints a capability URL. |
| `consent/accept-cmc` | Accepter writes to accept (carries the capability URL from the request). |
| `consent/refuse-cmc` | Accepter writes to refuse. |
| `consent/revoke-cmc` | Either party writes to revoke an established consent. |
| `message/chat-cmc` | Either party writes a chat to their per-peer chat stream. |
| `notification/alert-cmc` | Either party sends a system alert (level + title + body). |
| `notification/ack-cmc` | Acknowledge a previously-received alert. |
| `consent/scope-request-cmc` | Collector proposes a scope change. |
| `consent/scope-update-cmc` | User-side accepts / applies a scope change. |
| `consent/back-channel-cmc` | Plugin-internal handshake step. Apps don't write these. |

`consent/back-channel-cmc` is not app-facing — the plugin emits and consumes it transparently as part of the handshake.

## The handshake — a worked example

Imagine **Alice** (a study participant) wants to grant **Bob** (a research collector) read access to her `fertility` stream, with chat enabled.

**1. Alice creates an app-scope stream.** Once per app:

```js
await aliceConn.api([{ method: 'streams.create', params: {
  id: ':_cmc:apps:my-study', parentId: ':_cmc:apps', name: 'My Study'
}}]);
// Optionally a per-request sub-path for finer-grained scoping:
await aliceConn.api([{ method: 'streams.create', params: {
  id: ':_cmc:apps:my-study:cohort-2026', parentId: ':_cmc:apps:my-study', name: 'Cohort 2026'
}}]);
```

**2. Alice writes the consent request.** This triggers the capability mint:

```js
const res = await aliceConn.api([{ method: 'events.create', params: {
  streamIds: [':_cmc:apps:my-study:cohort-2026'],
  type: 'consent/request-cmc',
  content: {
    to: null,                               // null = open invite via capability URL
    capabilityRequested: true,
    request: {
      title:       { en: 'Cohort 2026 — share fertility data' },
      description: { en: 'Sharing fertility data with the cohort 2026 research team.' },
      consent:     { en: 'I consent to share my fertility data for cohort 2026 research.' },
      permissions: [ { streamId: 'fertility', level: 'read' } ]
    },
    requesterMeta: { username: 'alice', appId: 'my-study' }
  }
}}]);
const triggerId = res[0].event.id;
```

The plugin stamps `content.capabilityUrl` on the trigger event within milliseconds. Alice's app reads it back and shares it with Bob (via email, QR code, etc.).

**3. Bob accepts via the capability URL:**

> Bob's `bobConn` must be authenticated with a **personal** access token. Pryv.io rejects `consent/accept-cmc` writes from app- or shared-access tokens (`400 invalid-operation` + `error.data.id === 'cmc-accept-requires-personal-token'`) because the trigger event is treated as the user's authoritative consent — the personal-token requirement enforces user-presence at the moment of acceptance. Apps that hold only an app/shared token use the [accept hand-off](#accept-hand-off-app-without-a-personal-token) below; the lib helper opens an auth page where Bob signs in and the trigger is written with the fresh personal token.

> **A delegate may accept for an account it manages.** With [account delegation](/guides/account-delegation/), a carer's delegate token for the managed account counts as personal and may write this `consent/accept-cmc` (open-pryv.io 2.0.0-rc.30 or later). The data grant then records the delegation, the accept event carries a server-stamped `content.approvedBy`, and removing the delegate withdraws the grant with a `consent/revoke-cmc` to the requester. See [Consent given by a delegate](/guides/account-delegation/#consent-given-by-a-delegate).

```js
await bobConn.api([{ method: 'events.create', params: {
  streamIds: [':_cmc:apps:my-study'],   // Bob's local app-scope stream
  type: 'consent/accept-cmc',
  content: { capabilityUrl, accessName: 'cmc-cohort-2026' }
}}]);
```

The plugin on Bob's side:
- reads the offer via the capability,
- mints a **data-grant access** on Bob's account (with `fertility:read` + the chat / system anchor permissions),
- delivers `consent/accept-cmc` back to Alice's `:_cmc:_internal:responses:<capId>` stream.

**4. Alice's side automatically:**
- mints the **back-channel access** for Bob,
- provisions the chat / collectors anchor streams,
- POSTs `consent/back-channel-cmc` to Bob's `:_cmc:inbox` (so Bob's data-grant gets the back-channel apiEndpoint stamped on it),
- mirrors a copy of the accept event onto Alice's own `:_cmc:inbox` so Alice's app sees it.

Alice's app subscribes to `:_cmc:inbox` to be notified:

```js
const aliceConn2 = new pryv.Connection(aliceApiEndpoint);
const monitor = aliceConn2.monitor({ streams: [':_cmc:inbox'] });
monitor.on('event', (event) => {
  if (event.type === 'consent/accept-cmc' && event.content?.from?.username === 'bob') {
    console.log('Bob accepted! Data-grant URL:', event.content.grantedAccess.apiEndpoint);
  }
});
```

After the handshake, both sides have:
- a chat stream `:_cmc:apps:my-study:cohort-2026:chats:<peer-slug>`,
- a system channel `:_cmc:apps:my-study:cohort-2026:collectors:<peer-slug>`,
- the access pair pre-wired for bi-directional delivery.

## Sending chat messages

To chat, write `message/chat-cmc` to your per-peer chat stream:

```js
const cmc = require('@pryv/cmc');
const peerSlug = cmc.counterpartySlug({ username: 'bob', host: 'pryv.example' });
const myChatStream = cmc.chatStreamUnder(':_cmc:apps:my-study:cohort-2026', peerSlug);

await aliceConn.api([{ method: 'events.create', params: {
  streamIds: [myChatStream],
  type: 'message/chat-cmc',
  content: { content: 'Hello from Alice' }
}}]);
```

The plugin delivers the chat to Bob's matching chat stream within ~100ms. Bob's app subscribes to the same stream-id pattern (with Alice's slug) to read incoming chats.

**Features gating.** If the original invite was issued with `content.request.features.chat: false`, both sides' `events.create` rejects with `cmc-chat-disabled` and no delivery happens. The flag is binding on the relationship's lifetime; default-permit on omission. Use `cmc.sendChat()` for the lifecycle-aware wrapper that surfaces the rejection as a `CmcError({ id: cmc.errorIds.CHAT_DISABLED })`.

## Sending system notifications

System notifications carry richer structure than chats — a level (info / warning / critical), localised title + body, and optionally an ack-request:

```js
const myCollectorStream = cmc.collectorStreamUnder(':_cmc:apps:my-study:cohort-2026', peerSlug);

await collectorConn.api([{ method: 'events.create', params: {
  streamIds: [myCollectorStream],
  type: 'notification/alert-cmc',
  content: {
    level: 'warning',
    title: { en: 'Daily survey reminder' },
    body:  { en: 'You haven\'t submitted today\'s survey yet.' },
    code:  'survey-reminder',
    ackRequired: true
  }
}}]);
```

If `ackRequired` is true, the recipient sends a `notification/ack-cmc` back referencing the alert event-id.

**Features gating.** Mirrors the chat behaviour: `features.systemMessaging: false` on the original invite blocks `notification/alert-cmc` + `notification/ack-cmc` sends with `cmc-system-messaging-disabled`. `consent/scope-request-cmc` and `consent/scope-update-cmc` are protocol-level and remain permitted regardless of the flag.

## Revoking

Either party can revoke the consent at any time:

```js
await aliceConn.api([{ method: 'events.create', params: {
  streamIds: [':_cmc:apps:my-study:cohort-2026'],
  type: 'consent/revoke-cmc',
  content: {
    accessId: backChannelAccessId,         // the local access being revoked
    reason: { en: 'study complete' }
  }
}}]);
```

The plugin tears down both sides of the access pair. The chat / collectors history is preserved (events are not deleted) but no further messages will be delivered.

**The withdrawal is recorded on the person's consent.** However the consent ends, the `consent/accept-cmc` event the person wrote to accept it (in their `:_cmc:apps:<app>` scope) records it in `content.withdrawal = { at, by, accessId, revokeEventId? }`, `at` in seconds and `accessId` the data grant that was deleted. Requires open-pryv.io 2.0.0-rc.36 or later.

```json
{ "content": { "withdrawal": { "at": 1791200000, "by": "revoke-cmc", "accessId": "cdatagrant00001", "revokeEventId": "crevoke0000001" } } }
```

| `by` | How the consent ended |
|---|---|
| `accesses.delete` | The data grant was deleted with [`accesses.delete`](/reference/#methods-accesses-accesses-delete). |
| `revoke-cmc` | The person wrote a `consent/revoke-cmc`, as above; `revokeEventId` is that event. |
| `peer-revoke` | The requester revoked; `revokeEventId` is the `consent/revoke-cmc` that arrived in the person's inbox. |
| `delegation-detach` | The consent was given by a delegate who was then removed, and the owner did not keep it (see [account delegation](/guides/account-delegation/#consent-given-by-a-delegate)). This record is `{ at, by, relId }`, `relId` naming the delegation. |

- The record is written by the server only: a client-supplied `withdrawal` is dropped on create, an update keeps the stored value, and once set it is never overwritten (the first record stays).
- It is written on the accepting side only, on the event that gave the consent.
- After `accesses.delete`, it lands shortly after the call answers, and the user's socket clients receive `eventsChanged` when it does.
- A consent accepted on an older core whose data grant does not point back to its accept event has nothing to mark: the audit log remains its record.

**Listing consents.** An app that lists the person's consents should treat an accept event carrying `withdrawal` as ended. Since `@pryv/cmc` 3.18.0, `cmc.listAcceptedRelationships` leaves withdrawn relationships out by default; pass `includeWithdrawn: true` to list them too. Every record carries `withdrawal`, `null` while the relationship is active. On an older core, which records only the `delegation-detach` withdrawal, the other ended relationships still look active.

## Lib-js helpers

CMC client helpers live in the **sibling package** [`@pryv/cmc`](https://www.npmjs.com/package/@pryv/cmc) — install alongside `pryv`:

```
npm install pryv @pryv/cmc
```

```js
const pryv = require('pryv');
const cmc = require('@pryv/cmc');

// Level-0 — pure helpers (no network):
cmc.NS;                                                                  // ':_cmc:'
cmc.appScope('my-app');                                                  // ':_cmc:apps:my-app'
cmc.counterpartySlug({ username: 'bob', host: 'pryv.example' });         // 'bob--pryv-example'
cmc.chatStreamUnder(':_cmc:apps:my-app:study-A', 'bob--pryv-example');
// → ':_cmc:apps:my-app:study-A:chats:bob--pryv-example'

// Level-1 — lifecycle wrappers (take a pryv.Connection):
const conn = new pryv.Connection(aliceApiEndpoint);

// Provider issues an invite (writes consent/request-cmc + waits for capabilityUrl).
const { inviteEventId, capabilityUrl } = await cmc.createInvite(conn, {
  appCode: 'my-study',
  scopeStreamId: ':_cmc:apps:my-study:cohort-2026',
  displayName: 'My study',
  requestedPermissions: [{ streamId: 'fertility', level: 'read' }],
  mode: 'single-use',
  // Optional: 'app' issues a delegable data-grant (the requester can then
  // accesses.create scoped sub-accesses); omit for the default 'shared'.
  // accessType: 'app',
  // Optional per-invite expiry (Unix seconds); omit for the 7-day default.
  // single-use: must resolve to [60s, 30d]. open-link: at least 60s, no upper
  // bound, or `expiresAt: null` for a link that never expires (ends with
  // cmc.invalidateCapability). Out of range: cmc-capability-ttl-out-of-range;
  // null on single-use: cmc-capability-no-expiry-not-allowed.
  // expiresAt: Math.floor(Date.now() / 1000) + 3600,
  // Optional features negotiation — omitted defaults to true for both.
  // Setting either to false makes that channel binding-disabled for the
  // resulting relationship; sends will reject with cmc-chat-disabled /
  // cmc-system-messaging-disabled.
  features: { chat: true, systemMessaging: true },
});

// Accepter accepts (returns local data-grant access id + counterparty identity).
const { dataGrantAccessId } = await cmc.acceptInvite(bobConn, capabilityUrl, {
  scopeStreamId: ':_cmc:apps:my-study',
});

// Provider polls inbox for the accept arrival.
const { grantedAccessApiEndpoint } = await cmc.waitForAccept(conn, {
  fromUsername: 'bob', appCode: 'my-study', timeoutMs: 15000,
});

// Either side can chat / alert / revoke:
await cmc.sendChat(conn, { scopeStreamId, peerSlug, content: 'Hello' });
await cmc.sendSystemAlert(conn, { scopeStreamId, peerSlug, level: 'info',
  title: { en: 'Reminder' }, body: { en: 'Daily survey reminder' } });
await cmc.revokeRelationship(conn, { inviteEventId });
// or revoke from accepter side by data-grant access id:
await cmc.revokeAcceptance(bobConn, { scopeStreamId, accessId: dataGrantAccessId });

// Frozen catalogue mirroring the server-side error ids.
cmc.errorIds.CAPABILITY_TTL_OUT_OF_RANGE;     // 'cmc-capability-ttl-out-of-range'
cmc.errorIds.CAPABILITY_NO_EXPIRY_NOT_ALLOWED; // 'cmc-capability-no-expiry-not-allowed'
cmc.errorIds.CHAT_DISABLED;                   // 'cmc-chat-disabled'
cmc.errorIds.SYSTEM_MESSAGING_DISABLED;       // 'cmc-system-messaging-disabled'
cmc.errorIds.CLIENTDATA_CMC_FORBIDDEN;        // 'cmc-clientdata-cmc-forbidden'
cmc.errorIds.RESERVED_STREAM_UNDELETABLE;     // 'cmc-reserved-stream-undeletable'
cmc.errorIds.COUNTERPARTY_IDENTITY_MISSING;   // 'cmc-counterparty-identity-missing'
// + the lifecycle / handler / chat-routing ids — see source for the full list.
```

Full surface + JSDoc: [`@pryv/cmc/src/index.js`](https://github.com/pryv/lib-js/blob/master/components/pryv-cmc/src/index.js). Mirror of the server-side `CmcErrorIds` lives at [`components/cmc/src/errorIds.ts`](https://github.com/pryv/open-pryv.io/blob/master/components/cmc/src/errorIds.ts).

## Accept hand-off (app without a personal token)

`acceptInvite` posts the consent/accept-cmc trigger directly. Since Pryv.io gates that trigger AND `consent/scope-update-cmc` to **personal tokens only**, apps that hold only an app- or shared-access token can't accept or scope-update directly: they delegate to the Pryv auth pages. (Revoke uses a different gate — see below.)

`@pryv/cmc` ≥ 3.9 ships hand-off helpers for accept + scope-update:

```js
// URL-only — caller drives navigation (custom popup, mobile deep-link, etc.).
const url = cmc.requestAcceptUrl({
  authUrl: 'https://account.pryv.me/cmc-accept',          // /cmc-accept route on the auth pages
  pryvApi: 'https://reg.pryv.me/',                         // accepter's Pryv API base
  capabilityUrl,                                            // from the requester's invite (out-of-band)
  scopeStreamId: ':_cmc:apps:my-study',                    // accepter's own :_cmc:apps:* stream
  // returnUrl: 'https://your-app.example.com/accepted'    // switches to redirect mode
});

// Popup + postMessage (browser-only).
const result = await cmc.requestAccept({
  authUrl, pryvApi, capabilityUrl,
  scopeStreamId: ':_cmc:apps:my-study'
});
// result = { ok: true, acceptEventId }  (acceptEventId is an id on the accepter's account)
// Rejects with CmcError on popup-closed / popup-blocked / timeout / server failure.

// Redirect mode (full-page navigation; the auth page redirects back via location.assign).
await cmc.requestAccept({
  authUrl, pryvApi, capabilityUrl,
  scopeStreamId: ':_cmc:apps:my-study',
  returnUrl: 'https://your-app.example.com/accepted'
  // → location.assign('https://your-app.example.com/accepted?cmcAcceptResult=<json>')
});
```

The `/cmc-accept` page renders the offer details (requester identity, requested permissions, consent message), prompts the user to sign in with their Pryv credentials, writes the consent/accept-cmc trigger with the fresh personal token, and returns the outcome to your app via popup `postMessage` (default) or `returnUrl` redirect. The outcome carries no credential: the requester gets the data-grant endpoint on its own side, from `cmc.waitForAccept` (`grantedAccessApiEndpoint`).

Same shape for scope-update:

```js
const result = await cmc.requestScopeUpdate({
  authUrl: 'https://account.pryv.me/cmc-scope-update',
  pryvApi,
  scopeRequestEventId: 'evt-scope-req-abc123',         // from the collector's proposal on YOUR account
  // scopeStreamId is optional — defaults to the scope-request event's home stream
});
// result = { ok: true, updateEventId, action: 'accept' | 'refuse' }
```

`pryv.cmc.requestScopeUpdateUrl(opts)` builds the URL only for caller-driven navigation. Same `mode: 'popup' | 'redirect'` + `returnUrl` semantics as `requestAccept`.

**Revoke does NOT need a hand-off.** `consent/revoke-cmc` is access-permission-gated server-side (via `AccessLogic.canDeleteAccess` — the standard rule `accesses.delete` uses), which honours the `selfRevoke` feature permission on the target. Apps holding the relationship's data-grant access can self-revoke directly via `cmc.revokeAcceptance(...)` / `cmc.revokeRelationship(...)` from any token class. Unauthorised attempts fail with `error.data.id === 'cmc-revoke-forbidden'`.

## Consent invites in the authorisation request

An app that holds invites for the user (capability URLs that requesters sent it, for example with an onboarding link) can ask the user to answer them in the same [auth request](/reference/#auth-request) (`POST /reg/access`) that grants the app its own access. The user signs in once and decides on the app access and on every invite on one page, instead of going through one [accept hand-off](#accept-hand-off-app-without-a-personal-token) per invite. This requires open-pryv.io 2.0.0-rc.32 or later, and an authentication page that supports it, such as app-web-user-account 0.11.0 or later.

### What the app sends

The auth request carries an optional `cmcInvites` list beside `requestedPermissions`:

```json
{
  "requestingAppId": "kid-health",
  "requestedPermissions": [
    { "streamId": "health", "level": "contribute", "defaultName": "Health" }
  ],
  "cmcInvites": [
    { "capabilityUrl": "https://cmc.example.com/…", "mandatory": true },
    { "capabilityUrl": "https://cmc.other.example/…", "for": "target", "accessName": "Kid Health sharing" }
  ]
}
```

| Field | Value |
|---|---|
| `capabilityUrl` | The invite's capability URL, as the requester shared it: an absolute `http` or `https` URL of at most 2048 characters. |
| `mandatory` | Optional boolean, default `false`. `true` when your app cannot work without this consent: declining it ends the whole request (see below). |
| `for` | Optional, `'self'` (default) or `'target'`. `'self'`: the signed-in account accepts. `'target'`: the account the access is granted for accepts, when the user grants it for an account they manage through [account delegation](/guides/account-delegation/#granting-an-app-access-for-a-controlled-account). |
| `accessName` | Optional, 1 to 256 characters: the name of the data grant the person mints by accepting this invite, stored as sent. The core does not use it; the authentication page passes it to the accept. Without it, the grant takes the platform's default name. Requires open-pryv.io 2.0.0-rc.36 or later: an older core refuses an entry carrying it with `400 invalid-parameters`, and no request is created. |

The list holds 1 to 8 entries, and an entry carries no other key. A malformed list is refused with `400 invalid-parameters` and no request is created. The request's overall size ceiling (`access:maxRequestBytes`) still applies. With lib-js, set `cmcInvites` in `authRequest`: it is sent as is.

**Detecting support.** The `201` answer echoes `cmcInvites`, normalised (`mandatory` and `for` filled in, `accessName` kept on the entries that carried it), only when the core understood the field; an older core drops it and echoes nothing. The `NEED_SIGNIN` poll carries the same list, which is how the authentication page reads it. Without the echo, send the user through the [accept hand-off](#accept-hand-off-app-without-a-personal-token) for each invite instead.

### What the authentication page does

The platform's reference authentication page, [app-web-user-account](https://github.com/pryv/app-web-user-account) 0.11.0 or later, handles the invites as follows.

1. **It shows the app access first, then each invite as its own block**: who asks, the consent text and the requested permissions, with the block's own Approve and Decline. Approving the app access never approves an invite. Approve and Decline only record the choice, which the user can still change; the page's Continue acts, and it is available once every invite has a decision.
2. **Some invites can only be declined.** The page accepts an invite on the requester's offer scope: the offer's origin stream, else `:_cmc:apps:<appId>` from the requester's metadata. An invite whose offer cannot be read, or whose scope cannot be determined, offers Decline only.
3. **On Continue, it decides, then accepts, then grants.**
   - A declined **mandatory** invite ends the request before anything is written: the page posts `REFUSED` with `reasonId: 'REFUSED_MANDATORY_CONSENT'`, and neither the app access nor any consent is created. Your poll receives that `REFUSED`.
   - A declined invite whose offer is readable gets a `consent/refuse-cmc` sent to the requester. This is best-effort: a refusal that cannot be sent never blocks, and the outcome stays `{ declined: true }`.
   - The approved invites are accepted (a `consent/accept-cmc` event, as in [the handshake](#the-handshake--a-worked-example)), mandatory ones first, then optional ones, each group in the request's order. An invite with `for: 'self'` is accepted with the signed-in user's own personal token; one with `for: 'target'` with the delegate token the page holds for the managed account, on that account's core, which makes it a [consent given by a delegate](/guides/account-delegation/#consent-given-by-a-delegate). When the user grants the access for their own account, a `for: 'target'` invite is accepted with their own token and reported as `acceptedFor: 'self'`. The data grant is named with the invite's `accessName` when it carries one (a page that does not know the field ignores it, and the grant takes the default name).
   - A mandatory invite that cannot be accepted ends the request `REFUSED` with `reasonId: 'MANDATORY_CONSENT_FAILED'`; its `message` names the invite and the platform's error id, and the app access is not created. Invites accepted before it stay accepted: nothing is rolled back.
   - An optional invite that cannot be accepted is reported as `{ reason }` and the page goes on. So is an accept whose wait ends before the platform records the outcome (`cmc-capability-timeout`), mandatory or not: it is never a refusal, as the accept may still complete.
   - The app access is created or updated **last**. When the app already holds the access the user is asked for, the page shows it beside the invites and hands it over unchanged, only after the invites are answered, so holding the access never bypasses a mandatory invite. The page then posts `ACCEPTED` with one outcome per invite, in the request's order.
4. **Delivery to the requester follows.** The accept is complete on the user's account when the page posts; the plugin delivers it to the requester, retrying if needed.

An authentication page that does not support invites ignores them: the request is answered for the app access alone, and the `ACCEPTED` body carries no `cmcInvites`.

### Outcomes in the `ACCEPTED` body

The `ACCEPTED` body carries `cmcInvites`: one outcome per invite, in the order of the request. It is present in the answer to the page's post and in every `ACCEPTED` poll, whether the token is delivered inline or through a [credential hand-off](/reference/#poll-request).

```json
{
  "status": "ACCEPTED",
  "username": "kim-doe",
  "apiEndpoint": "https://…@kim-doe.example.com/",
  "token": "…",
  "cmcInvites": [
    { "acceptEventId": "cacceptevent0001", "dataGrantAccessId": "cdatagrant00001" },
    { "declined": true }
  ]
}
```

| Outcome | Meaning |
|---|---|
| `{ acceptEventId, dataGrantAccessId?, acceptedFor? }` | Accepted. `acceptEventId` is the `consent/accept-cmc` event on the accepting account, `dataGrantAccessId` the data grant minted there when known. `acceptedFor: 'self'` marks a `for: 'target'` invite accepted by the signed-in account. |
| `{ declined: true }` | The user declined this (optional) invite. |
| `{ reason }` | The page could not complete this optional invite, or its accept was still pending when the wait ended (`cmc-capability-timeout`); `reason` says why. |

The core checks the list the page posts: the same number of entries as the request's invites and these shapes only, sent with `ACCEPTED` on a request that carried invites. Anything else is refused with `400 invalid-parameters` before anything is written.

**The outcomes are a hint, not a proof.** They are what the authentication page reports; the core does not verify them, and `mandatory` is enforced by the page, not by the core. Use them to update your interface. The requester learns the truth from its own inbox: the `consent/accept-cmc` that arrives there (`cmc.waitForAccept`).

### Where the capability URLs are kept

A capability URL lets whoever holds it read the offer. The URLs stay in the access request, which lives only in the memory of the core that created it: at most one hour, and 120 seconds after its outcome is first read. Whoever holds the request's poll key can read them, as the rest of the request (the `NEED_SIGNIN` poll carries the list). Share the poll URL no more widely than the invites themselves.

## Further reading

- [Implementer's Guide (open-pryv.io)](https://github.com/pryv/open-pryv.io/blob/master/components/cmc/IMPLEMENTERS-GUIDE.md) — the deep-dive reference for app developers integrating CMC.
- [Internals (open-pryv.io)](https://github.com/pryv/open-pryv.io/blob/master/components/cmc/INTERNALS.md) — operator / contributor reference, with full sequence diagrams.
- [Consent request guide](/guides/consent/) — the classical single-account consent flow; pair this guide with that one when designing your data-collection architecture.
- [Event types directory](/event-types/) — the canonical class/format catalogue, including the `consent/*`, `message/chat-cmc`, and `notification/*-cmc` types.
