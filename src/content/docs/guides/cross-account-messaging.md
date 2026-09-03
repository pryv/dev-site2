---
title: 'Cross-account Messaging & Consent (CMC)'
description: How to use CMC, Pryv.io's protocol for federated cross-account consent, chat and system notifications between two user accounts on any platform.
---


This guide describes how to use **CMC** — Pryv.io's built-in protocol for federated, cross-account consent, chat and system notifications. With CMC, two Pryv accounts (which may live on different platforms) can mutually issue and receive data-grants, exchange chat messages, and send system alerts — all on top of standard Pryv events / streams / accesses.

It complements the [Consent request guide](/guides/consent/), which covers the classical single-account consent flow (one app obtaining an access token on one user's account). CMC is what you reach for when consent flows BETWEEN two end-user accounts.

## Table of contents <!-- omit in toc -->
<!-- no toc -->
1. [When to use CMC](#when-to-use-cmc)
2. [Concepts](#concepts)
3. [Streams reserved by the plugin](#streams-reserved-by-the-plugin)
4. [Event types](#event-types)
5. [The handshake — a worked example](#the-handshake-a-worked-example)
6. [Sending chat messages](#sending-chat-messages)
7. [Sending system notifications](#sending-system-notifications)
8. [Revoking](#revoking)
9. [Lib-js helpers](#lib-js-helpers)
10. [Further reading](#further-reading)

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
  // Optional per-invite TTL override — server bounds to [60s, 30d];
  // omit for the 7-day default. Out-of-range rejects with
  // cmc-capability-ttl-out-of-range.
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
  authUrl: 'https://access.pryv.me/access/v3/cmc-accept', // /cmc-accept route on the auth pages
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
// result = { ok: true, dataGrantApiEndpoint, acceptEventId }
// Rejects with CmcError on popup-closed / popup-blocked / timeout / server failure.

// Redirect mode (full-page navigation; the auth page redirects back via location.assign).
await cmc.requestAccept({
  authUrl, pryvApi, capabilityUrl,
  scopeStreamId: ':_cmc:apps:my-study',
  returnUrl: 'https://your-app.example.com/accepted'
  // → location.assign('https://your-app.example.com/accepted?cmcAcceptResult=<json>')
});
```

The `/cmc-accept` page renders the offer details (requester identity, requested permissions, consent message), prompts the user to sign in with their Pryv credentials, writes the consent/accept-cmc trigger with the fresh personal token, and returns the data-grant apiEndpoint to your app via popup `postMessage` (default) or `returnUrl` redirect.

Same shape for scope-update:

```js
const result = await cmc.requestScopeUpdate({
  authUrl: 'https://access.pryv.me/access/v3/cmc-scope-update',
  pryvApi,
  scopeRequestEventId: 'evt-scope-req-abc123',         // from the collector's proposal on YOUR account
  // scopeStreamId is optional — defaults to the scope-request event's home stream
});
// result = { ok: true, updateEventId, action: 'accept' | 'refuse' }
```

`pryv.cmc.requestScopeUpdateUrl(opts)` builds the URL only for caller-driven navigation. Same `mode: 'popup' | 'redirect'` + `returnUrl` semantics as `requestAccept`.

**Revoke does NOT need a hand-off.** `consent/revoke-cmc` is access-permission-gated server-side (via `AccessLogic.canDeleteAccess` — the standard rule `accesses.delete` uses), which honours the `selfRevoke` feature permission on the target. Apps holding the relationship's data-grant access can self-revoke directly via `cmc.revokeAcceptance(...)` / `cmc.revokeRelationship(...)` from any token class. Unauthorised attempts fail with `error.data.id === 'cmc-revoke-forbidden'`.

## Further reading

- [Implementer's Guide (open-pryv.io)](https://github.com/pryv/open-pryv.io/blob/master/components/cmc/IMPLEMENTERS-GUIDE.md) — the deep-dive reference for app developers integrating CMC.
- [Internals (open-pryv.io)](https://github.com/pryv/open-pryv.io/blob/master/components/cmc/INTERNALS.md) — operator / contributor reference, with full sequence diagrams.
- [Consent request guide](/guides/consent/) — the classical single-account consent flow; pair this guide with that one when designing your data-collection architecture.
- [Event types directory](/event-types/) — the canonical class/format catalogue, including the `consent/*`, `message/chat-cmc`, and `notification/*-cmc` types.
