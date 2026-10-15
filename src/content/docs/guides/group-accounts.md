---
title: 'Group accounts: a practice, a team or a bridge sharing one account'
description: How a practice, a research team or a bridge service shares one Pryv account with its members, invites patients through cross-account messaging and reads their data under an access that names each member, without running a backend.
---

A **group account** is an ordinary Pryv account that a group of people works through: a medical practice, a research team, a bridge that connects a clinical system to Pryv. Patients share their data with the group once, through [cross-account messaging (CMC)](/guides/cross-account-messaging/), and the people of the group read it.

This guide covers two ways to do that:

- **Member accesses** (the main pattern): each person of the group signs in with their own Pryv account, joins the group, and reads a patient's data under an access that the group's core creates for them on the patient's account. The implementer ships a static web app and no server.
- **One access and a caller label** (the simpler alternative): the group holds one access per patient and a server of its own uses it for everyone, telling Pryv who is calling with a `callerId`.

It assumes you know the CMC handshake (requester, accepter, data grant, back-channel) from the [CMC guide](/guides/cross-account-messaging/).

## When a group shares one account

Use a group account when:

- **Patients consent to an organisation, not to a person.** A patient shares their diary with "the practice", and whoever is on duty reads it. Staff come and go; the patient should not have to consent again each time.
- **Each read must still name a person.** The patient, or an auditor, wants to see which member of the group opened the data, not just "the practice".
- **Leaving the group must end access.** When a member leaves, everything they could reach through the group goes with them, without asking every patient.

If one person consents to one other person (a patient and their own doctor), a plain CMC relationship between their two accounts is simpler. If one account must hold full control over another (a parent and a child), see [account delegation](/guides/account-delegation/).

## Choosing between the two patterns

| | Member accesses | One access and a caller label |
|---|---|---|
| Who holds credentials | Each member holds their own Pryv account and, per patient, their own short-lived access. | The group's server holds one access per patient and uses it for every member. |
| Backend | None: a static web app on `@pryv/cmc`. | Required: the shared token must never reach a member's browser. |
| What the patient's audit log names | The member's own access, created for them and named after them, "via" the group's grant. | The group's access, plus the `callerId` label the server sent. |
| Is the attribution verified | Yes: the member is stamped by the servers from authenticated accesses. | No: `callerId` is whatever the caller sends, unless a [custom auth step](/guides/custom-auth/) on the patient's platform checks it. |
| Ending one member's access | The group revokes the membership; the group's core deletes that member's accesses on patients' accounts. | The group's server stops serving that member. Nothing changes on the patient side. |
| Patient consent | A **delegable** grant (`accessType: 'app'`); the consent screen says so. | An ordinary grant (`'shared'`, the default). |
| Core versions | The group's and the members' cores run open-pryv.io 2.0.0-rc.53 or later; patients' cores 2.0.0-rc.52 or later, with attribution by name only below 2.0.0-rc.53 (see [Several cores and older releases](#several-cores-and-older-releases)). | Any core. |

**Use member accesses** when there is no server to run, when members work from their own devices, or when the patient should see who read their data on a record that the caller cannot write.

**Use one access and a caller label** when the group already runs a server that authenticates its staff and mediates every call (a hospital system, a research platform), when patients' cores cannot be upgraded, or when the patient's consent should not mention delegation. A static app that uses member accesses needs no `callerId`: each member already holds their own access.

The rest of this guide describes member accesses, then [the caller-label alternative](#the-alternative-one-access-and-a-caller-label).

## How member accesses work

Four kinds of accounts take part:

- **The group account**: the organisation's Pryv account. Its **teams** are CMC scope streams, `:_cmc:apps:<app>:<team>` (for example `:_cmc:apps:practice:team-a`).
- **Administrators**: the group account's owner, or [delegates](/guides/account-delegation/) of the group account, each with their own token.
- **Members**: ordinary Pryv accounts, one per person, on any core.
- **Patients**: ordinary Pryv accounts, on any core.

And five steps:

1. **A member asks to join.** From their own account, the member writes a membership request naming the group and the teams. It produces a capability URL, which the member shows to an administrator as a QR code or a link.
2. **An administrator approves.** The administrator opens the URL, chooses which of the requested teams to grant, and accepts with the group's token. The access this creates on the group account is the member's **membership**: it lets the member write in those teams. It also carries the plugin's own delivery channels, which the member's core uses for the membership's protocol messages; nothing a member's app can use beyond the teams.
3. **The member invites patients for the group.** Through the membership, the member publishes CMC invites from the group account. The patient accepts a **delegable** grant: the group may create narrower accesses from it.
4. **The member opens a patient's data.** The member asks the group's core for an access on that patient. The group's core creates it on the patient's core, through the patient's grant, names it after the member and returns it once. The member then calls the patient's core directly with it.
5. **Membership ends, accesses go.** When the membership ends, however it ends, the group's core deletes the accesses it created for that member on patients' accounts, and records what it removed.

No credential moves between cores: the patient's grant token stays on the group's core, and the member's access is produced by the patient's core.

## Setting up the group account

The group account is set up once, with its owner's personal token:

- **Create the team streams** under the app's scope, one stream per team. A member's membership covers a team stream and every stream under it.
- **Choose the administrators.** The owner can approve members; so can each delegate of the group account, which gives each administrator their own attributed token. A delegate administrator can accept and revoke memberships but cannot publish invites (members do), and cannot approve a membership requested from their own account.
- **Protect the account.** Whoever holds the owner's token, or a delegate token, holds every patient grant (see [The trust boundary](#the-trust-boundary)). Turn on [MFA](/reference/#multi-factor-authentication) for the owner and the delegates.

:::note[A delegate administrator leaving]
A membership approved with a delegate's token records that delegation, like any [consent given by a delegate](/guides/account-delegation/#consent-given-by-a-delegate). When that delegate is removed from the group account, the memberships they approved are deleted with it, unless the owner keeps them in the detach's `keepAccessIds`, and each deleted membership is swept (see [Ending access](#ending-access)). Review the list before removing an administrator.
:::

## Joining a group

A membership is a CMC relationship in which the **member is the requester** and the **group is the accepter**. The access minted on the group's account for the requester is the member's membership.

The member writes a `consent/request-cmc` on their own account with `request.membership: true` and permissions on the **group's** team streams. The server checks such an offer when it is written, and again when the group accepts it:

- stream permissions only, on team streams `:_cmc:apps:<app>[:<path>]` (not `*`, not the `chats` and `collectors` streams the plugin manages);
- level `read` or `contribute`, no higher;
- no feature permissions, and `accessType` absent or `'shared'`: a membership is never delegable;
- the administrator may always grant a subset of the teams (`allowUserChoice` is treated as `true`);
- no chat: `features.chat` is treated as `false`; the group can still send system alerts to the member.

An offer that breaks these rules is refused with `cmc-membership-permissions-invalid`, when written or when accepted. In particular, a membership can never ask for `:_cmc:inbox` on the group's account.

**The hand-off is the capability URL.** Nothing is delivered to the group automatically: the member shows the URL as a QR code or a link, and the administrator pastes or scans it. The request is single-use and expires like any CMC invite; an unaccepted request simply expires.

**Accepting is an administrator's act.** The accept is written with the group's personal token or a delegate token, as for any `consent/accept-cmc`; a membership cannot accept (`cmc-accept-requires-personal-token`). A delegate administrator cannot approve a membership requested from their own account: the accept fails with `cmc-membership-permissions-invalid`. The membership access then carries, in `clientData.cmc`:

```json
{ "role": "member",
  "membership": {
    "approvedBy": { "delegate": { "username": "admin-doe", "hostSlug": "example-core" }, "relId": "…" },
    "requestedScopes": [":_cmc:apps:practice:team-a", ":_cmc:apps:practice:team-b"]
  } }
```

`approvedBy` is `null` when the owner accepted. The member finds the membership's endpoint in the accept that arrives in their own `:_cmc:inbox`, marked `membership: true`.

**What a membership can do on the group account:** read and write the events of its teams: publish patient invites (`consent/request-cmc`) and ask for member accesses (`consent/member-access-cmc`). **What it cannot do:** accept invites or scope updates for the group (owner and delegates only), list or read the group's other accesses, read `:_cmc:inbox`, update or delete the team's member records (`cmc-protected-event-write`, see [What members can change](#the-trust-boundary)), or chat with the group (`cmc-member-channel-not-supported`).

## Inviting a patient

A member publishes the invite from the group account, through the membership, on a team stream. The invite must ask for a **delegable** grant: `accessType: 'app'` (see [Delegable data-grants](/guides/cross-account-messaging/#delegable-data-grants-shared-vs-app)). A `shared` grant cannot create accesses, and every later request for a member access on that patient fails with `cmc-member-access-grant-not-delegable`.

Use one single-use invite per patient. The invite's requester is the group account: the patient consents to the group, not to the member who sent the link.

**What the patient sees on the consent screen.** The offer as for any CMC invite: the group as requester, the consent text and the requested permissions. When the grant is delegable, an authentication page that supports it (app-web-user-account from its next release, on `/cmc-accept` and in the invites block of an [auth request](/guides/cross-account-messaging/#consent-invites-in-the-authorisation-request)) adds a notice to the offer. The reference app's wording, which operators can rebrand, is:

> This organisation can share this access with its team members. Each member's actions are recorded on your account.

Write the invite's consent text so that it agrees: who the group is, and that its members will read the data under their own names.

Members of a team see each other's invites, capability URLs included: the URL stays on the invite event. A colleague could accept an invite with their own account, which gains nothing but is a nuisance. To keep each member's invites apart, grant each member a membership on a sub-stream of their own, for example `:_cmc:apps:practice:team-a:dr-who`; a member whose membership covers `team-a` still sees the streams under it.

An open-link invite is closed with `consent/invalidate-link-cmc` written on the invite's stream or on a stream above it. Written elsewhere, it fails with `cmc-invalidate-link-scope-mismatch` and the link stays open, so a member cannot close the invites of a team they are not in by naming their capability ids. The invite's stream is read from the server's own copy of the offer, which no client can edit or delete, so an invite event a member deleted can still be closed.

## Opening a patient's data

Once the patient has accepted, the member asks the group's core for an access by writing a `consent/member-access-cmc` event, through the membership, on a team stream:

```json
{ "streamIds": [":_cmc:apps:practice:team-a"],
  "type": "consent/member-access-cmc",
  "content": {
    "counterparty": { "username": "patient-doe", "host": "pryv.example" },
    "permissions": [ { "streamId": "diary", "level": "read" } ],
    "expireAfter": 3600
  } }
```

| Field | Meaning |
|---|---|
| `counterparty` | The patient. Required. |
| `scopeStreamId` | Optional. The scope of the patient's relationship: the stream the event is written on (the default) or a stream under it. |
| `permissions` | Optional. Stream permissions only, each on exactly a stream id the group's invite offered the patient outside `:_cmc:` (a stream under an offered one is refused), at a level no higher than the offered one. Never `*`, never a `:_cmc:` stream. Default: the offered streams at `read`. |
| `expireAfter` | Optional, in seconds. Default 24 hours, at least 60 seconds, at most 7 days (per-core settings), and never beyond the grant's own expiry or the membership's (see below). |

There is no name field: the server names the access.

**The access never outlives the membership.** When the membership access has an expiry, `expireAfter` is capped at what is left of it, and the request is refused with `cmc-member-access-expiry-out-of-range` when less than the minimum (60 seconds by default) remains.

**The group's core checks, then creates.** It checks that the event was written with a membership (`cmc-member-access-not-member` otherwise, personal and delegate tokens included), that the patient's relationship exists and its handshake is complete (`-relationship-not-found`) and that it lies under the stream the event was written on (`-scope-outside-membership`), that the permissions are within what the group's invite offered (`-permissions-not-subset`), and the expiry (`-expiry-out-of-range`). It then creates the access on the patient's core, through the patient's grant. The patient's core checks again that the access stays within the grant.

**The answer carries the access, once.** The request is answered synchronously:

```json
{ "event": { "id": "…", "type": "consent/member-access-cmc", "content": { "status": "completed", "…": "…" } },
  "memberAccess": {
    "apiEndpoint": "https://…@patient-doe.pryv.example/",
    "accessId": "…",
    "name": "cmc-member--…",
    "expires": 1791203600,
    "attribution": "stamped"
  } }
```

The `event` is the stored row, read again after the access was created: its `content.status` is `completed` on success and `failed` otherwise.

The `apiEndpoint` carries the access's token. The server returns it in this answer only: it is never stored on the event, never logged, never retried. Do not log it or store it beyond the session; ask again when it expires. The stored event keeps `memberAccess` without the endpoint (`accessId`, `name`, `expires`, `attribution`), with `member` and `relationshipAccessId`, as the group's record of who opened which patient.

When the request fails after it was written (the patient's core refused or could not be reached), the answer has no `memberAccess` and the event's `content.status` is `'failed'`, with `content.failure.reason` giving the error id. A failure never records the patient core's answer body, only its error id and HTTP status.

**The access on the patient's account** is a `shared` access, created by the grant:

- it reaches only that patient, within the grant's permissions, and expires as asked;
- it cannot call `accesses.*`, so it cannot create or reveal any other access;
- its name names the member: `cmc-member--<member>--<hash>`, derived by the server;
- its `clientData.cmc` records, stamped by the two cores from authenticated accesses and never from the request:

```json
{ "role": "member-child",
  "member": { "username": "dr-who", "host": "pryv.example" },
  "group": { "username": "practice", "host": "pryv.example" },
  "viaAccessId": "…",
  "scopeStreamId": ":_cmc:apps:practice:team-a",
  "appCode": "practice" }
```

The member's username and host come from the group's core, which reads them from the membership; the group's identity and the grant (`viaAccessId`) come from the patient's core, which reads them from the grant that called it. The group's core sends only `{ role: 'member-child', member: { username, host } }`, two strings of 1 to 200 characters without whitespace, control, bidirectional or zero-width characters; the patient's core refuses anything else from a grant with `cmc-member-stamp-invalid`. No one can write, change or remove `clientData.cmc` on an access through the API.

**Asking again** for the same patient with exactly the same permissions returns the same access while it has more than five minutes left; other permissions (more or fewer), or an access about to expire, are replaced, and one the patient deleted is created again while the grant lasts. An access is never created over one the patient's core did not confirm gone: if that core cannot be reached while the previous access is being replaced, the request fails with `cmc-member-access-peer-unreachable` and the previous access stays recorded for the sweep. A member has one request in flight at a time per patient (`cmc-member-access-in-flight`) and at most 30 per minute per server process (`cmc-member-access-rate-limited`, ask again after the minute). In-flight and an unreachable patient core (`cmc-member-access-peer-unreachable`) are worth retrying shortly; `isMemberAccessRetryable` in `@pryv/cmc` says which.

## What the patient sees in the audit log

On the patient's account, every call made with a member access is recorded under that access's id, reads included with the default audit configuration (see [Audit logs](/guides/audit-logs/)). The access itself tells the patient who acted:

- **Its name and `clientData.cmc`** name the member and the group.
- **Its creator is the group's grant.** The access's `createdBy` is the grant, so the access details page of app-web-user-account (from its next release) shows "via <grant name>" with a link to the grant.
- **A removed access keeps its name.** After a member access is deleted (expired, swept, or withdrawn), the page resolves it from its deletion record ([`accesses.get`](/reference/#get-accesses) with `includeDeletions`), marks it removed with the date, and keeps its audit trail. On a patient core older than open-pryv.io 2.0.0-rc.53, see [Several cores and older releases](#several-cores-and-older-releases).
- **A `callerId` is a label, not an identity.** If a member's app sends one, it is recorded, and the same app-web-user-account release shows it as "Caller label (not verified)". Who acted is the access, not the label.

On the group's account, each `consent/member-access-cmc` event is created by the member's membership and names the member and the patient; each offboarding sweep is recorded as a `consent/member-revoke-cmc` event (below).

## Ending access

**The patient withdraws.** The patient revokes the group's grant from their consent pages (`consent/revoke-cmc`), or deletes it with [`accesses.delete`](/reference/#methods-accesses-accesses-delete). Every member access created from that grant is deleted with it, on the patient's own core, whether or not the group's core is reachable. The group receives the revoke as for any CMC relationship. This requires open-pryv.io 2.0.0-rc.52 or later on the patient's core; on an older one, see [Several cores and older releases](#several-cores-and-older-releases).

The patient can also delete one member's access, but while the grant lasts that member can ask for a new one. To stop the group, the patient withdraws the grant; to stop one member, the group offboards them.

**The group ends a patient relationship.** The group's core first deletes, through the grant, the member accesses it created on that patient, then delivers the revoke, then removes its own side. This pass writes no sweep record: a member access the patient's core did not confirm deleted is logged and lasts until it expires.

**Revoke notices are re-sent.** When the other core cannot be reached (network error, timeout, 5xx) after the attempts made during the request, the revoke notice is queued and re-sent by the sender's retry loop after 1, 5 and 25 minutes, about 2 hours, then every 6 hours: 8 re-sends over about 27 hours, after which it is marked `failed-permanent` for the operator. The `consent/revoke-cmc` event then reports `content.deliveryQueued: true` beside `content.peerNotified: false`. A 4xx is the other core's answer and is not retried. This holds on every core from open-pryv.io 2.0.0-rc.53, whoever revokes: the group, a member leaving, or a patient withdrawing from a core of that release or later. Deleting a relationship access with `accesses.delete`, or removing a delegate administrator, queues its notices the same way. A notice that lands late, after the two accounts accepted the same link again, ends nothing: its arrival is marked `content.superseded: 'relationship-re-established'`, which is informational, so keep your endpoints (see [Revoking](/guides/cross-account-messaging/#revoking) in the CMC guide). **Not queued (a known limitation):** the notices sent while an account is being deleted. No account is left to hold them, and holding the deletion until every other core answers would let an outage elsewhere block an erasure: they are attempted during the deletion, then logged as lost. Nothing is queued either when the retry loop is off (see [Operator settings](#several-cores-and-older-releases)).

**A membership ends.** However it ends, the group's core runs one **offboarding sweep** for that member:

| `reason` | How the membership ended |
|---|---|
| `revoke` | An administrator revoked it, or the member left (the member revokes their half of the relationship). |
| `accesses.delete` | The membership access was deleted with `accesses.delete`. |
| `expired` | The membership access expired (found by the periodic pass). |
| `vanished` | The membership access is gone but member accesses created for it were still recorded as live (found by the periodic pass: a deletion whose own sweep did not complete). |
| `narrowed` | The membership access was updated to fewer teams, or a team stream it covers was deleted for good (see below): only the patients outside the teams the membership still covers when the sweep runs are swept. |
| `detach` | The delegate administrator who approved it was removed, and the owner did not keep it. |
| `account-deleted` | The group account was deleted. Its member accesses on patients' cores are deleted through the grants before the account is erased; no record is kept, since the account is gone. |

**A team stream deleted for good** is a narrowing. When the group deletes a stream under `:_cmc:apps` for good (the second `streams.delete`, once the stream is trashed), every membership whose teams include that stream, lie under it or lie above it is swept as `narrowed` for the patients under that stream: the member accesses created there are deleted on the patients' cores. The record is written on the deleted stream's parent (or on `:_cmc:apps`) and names the stream in `uncovered`. Trashing a stream is not a narrowing: its member accesses stay until it is deleted or they expire.

The sweep deletes each member access the group's core created for that member, through the patient's grant, then reads back. Except at account deletion, it is recorded by the server as a `consent/member-revoke-cmc` event on the membership's team stream (client writes of that type are refused with `cmc-protected-event-write`):

| Field | Content |
|---|---|
| `member` | The member, `{ username, host }`. |
| `membershipAccessId` | The membership access that ended. |
| `reason` | How it ended: one of the values above (`revoke`, `accesses.delete`, `expired`, `vanished`, `narrowed`, `detach`). |
| `uncovered` | Present when a team stream was deleted: the stream ids gone. |
| `records` | The member accesses to delete: `{ relationshipAccessId, counterparty, childAccessId, expires }` each. |
| `status` | `pending`, `delivered`, `completed` or `failed`. |
| `outcome` | Per access, `{ childAccessId, result }`, `result` being `deleted`, `absent` (already gone, or expired) or `residual` (still there). |
| `residuals` | The accesses left in place, `{ counterparty, childAccessId, expires, reason }` each. |
| `failure` | `{ reason: 'cmc-member-revoke-residual', detail }` when accesses were left in place. |

The record is server-owned: an app or shared access, a membership included, cannot update or delete it (`cmc-protected-event-write`).

**Residuals.** A patient core that cannot be reached or refuses the deletion, or a relationship that cannot be read, leaves a residual, and the sweep record fails with `cmc-member-revoke-residual`. The sweep is retried through the retry queue (6 attempts over about 30 minutes); after that, the periodic ledger pass of the group's core sweeps residuals again, up to 50 per pass, every minute by default. The same pass sweeps memberships that expired or vanished. Both run with the CMC retry loop, `cmc:retryLoop:enabled`, which is on by default from open-pryv.io 2.0.0-rc.53. With it off, nothing is queued, the core logs a warning at boot, and a residual lasts until the access expires.

Expiry bounds every residual: at most 7 days with the default settings, 24 hours for an access asked with the default expiry, and never beyond the membership's own expiry. Keep `expireAfter` short to keep that window short. Residuals are listed on the sweep event (`residuals`) with their expiry.

## The trust boundary

**Pryv attributes to the credential, not to the human.** The patient's audit log says which access acted. A member access names the member whose membership asked for it; it does not prove that this person was at the keyboard. A member who shares their Pryv login, or hands their access to someone else, has that person's reads recorded under their own name. Keeping credentials personal is the group's responsibility. The member's name is the one their membership records, as their own platform presented them: it is as trustworthy as that platform, and the patient's audit log shows the group's grant beside it.

**What an arrival's sender proves.** `content.from = { username, host }` is written by the sending core (never by its app) and the arrival is bound to the access it was written with, so it identifies the account that holds that access on yours: an app of the sender cannot forge it. What a group's core asserts about one of its members (`member: { username, host }`) is that core's claim, checked by the member's own core when the membership was requested, not by yours.

**Read on `:_cmc:inbox` is holding every grant.** Each accept that arrives in an account's `:_cmc:inbox` carries the data grant's endpoint, token included. Any access with `read` on the group's `:_cmc:inbox` therefore holds every patient's grant, and can do with it anything the grant allows, without a member name. The same holds on a member's own account for their membership. Grant `read` on `:_cmc:inbox` only to what you would trust with all of them; a membership can never have it. No CMC offer can ask for it either: an offer naming a stream the plugin manages on the accepter's account (`:_cmc:inbox`, the `:_cmc:_internal` streams, a `chats` or `collectors` stream, the `:_cmc:apps` root) is refused when written (`cmc-invalid-event-content`) and again by the accepter's core when accepted (`cmc-offer-stream-not-offerable`), whatever the requester's core checked. `*` and the accepter's own `:_cmc:apps:<app>[:<path>]` streams stay offerable.

**The owner and the delegates hold every grant.** The group's owner, and each delegate of the group account (owner-equivalent), can read the inbox and act with any grant. This is the group-administrator risk: protect these accounts with MFA, prefer delegates (each attributed and removable) to sharing the owner's login, and remember that the patient's audit log attributes such calls to the grant, not to a member.

**What members see of each other.** Members of a team read the team's events: the invites (with their capability URLs), and each `consent/member-access-cmc` event, which says who opened which patient and when, with the access's id, name and expiry, but never its token. Use per-member sub-streams where that matters.

**What members can change.** The team's records live on the team stream. The member records, `consent/member-access-cmc` and `consent/member-revoke-cmc`, cannot be updated or deleted with an app or shared access, a membership included (403 `forbidden`, `cmc-protected-event-write`): only a personal token can, the owner's or a delegate administrator's. A member holding `contribute` on the team stream can still edit or delete the patient invites published there, from which the group's core reads what a member access may cover. Deleting such an invite blocks every member's requests for that patient with `cmc-member-access-relationship-not-found` (`error.data.reason: 'offer-not-found'`) until the group invites the patient again; nothing widens, since the patient's grant stays the real bound. Give `contribute` on team streams to members you trust with the team's invites. The patient's own audit trail (the deletion records and the member stamps on the patient's core) does not depend on them.

**The membership is itself a credential at rest.** Like any CMC grant, the membership's endpoint is stored in the member's `:_cmc:inbox` and on the back-channel. An app on the member's account that reads the inbox can act as the member in the group.

## What stays your job

Pryv provides the membership, the per-member access, the attribution and the offboarding. The implementer and the group still own:

- **Who is a member.** Vetting each person before approving their membership, and revoking memberships when people leave. Pryv offboards an account; it does not know who works where.
- **Personal credentials.** One Pryv account per person, MFA where it matters, no shared logins; and not logging or storing the member accesses.
- **The app.** Signing in, showing and scanning the membership QR code, listing the member's patients, asking again for an access when it expires or when the answer says to retry.
- **The teams.** Creating the team streams, choosing who is granted which, and at which level (`contribute` lets a member edit or delete the team's patient invites). Deleting a team stream for good offboards its members from the patients under it.
- **Watching the sweeps.** Keeping the retry loop on, checking residuals after an offboarding, and contacting the patients' operators when a core stays unreachable.
- **Everything outside Pryv.** The group's agreements with its members and patients, its role under the applicable regulations, and how data read by members is used once it leaves Pryv.

## Several cores and older releases

Members, the group and patients may each be on a different core, and on different platforms. The group's core calls the patient's core over HTTPS with the grant, even when both accounts are on the same core; the grant's token never leaves the group's core. The member access's token is produced by the patient's core, passes through the group's core once in the answer, and is then used by the member directly against the patient's core.

**Versions.** Both the group's core and the member's core run open-pryv.io 2.0.0-rc.53 or later, the group's core with the retry loop on (the default). The group's core creates the member accesses and runs the sweeps. The member's core runs the requester side of the membership: it checks the membership request, creates the group's back-channel on the member's account and marks the accept that arrives in the member's inbox as a membership. Against an older group core, `requestMemberAccess` throws `cmc-member-access-unsupported`.

**A patient core older than open-pryv.io 2.0.0-rc.53** does not accept the member stamp. The group's core then creates the access without it and reports `attribution: 'name-only'`: the access name still names the member, but `clientData.cmc` does not. This fallback is allowed by default for one release cycle (`cmc:memberAccess:allowNameOnly`), after which the default refuses it and the request fails with `cmc-member-access-peer-rejected`. Any other refusal of the patient's core is a failure, never a silent fallback. On such a core, a withdrawal from the consent pages deletes the member accesses without a deletion record: their past audit entries lose their name. A sweep, expiry, or the patient deleting a member access itself keep it.

**A patient core older than open-pryv.io 2.0.0-rc.52** does not delete the member accesses when the patient withdraws from the consent pages: they stay in place until they expire. Keep their expiry short, or ask such patients to delete the grant with `accesses.delete`, which removes the accesses created from it on older releases too.

**Operator settings** on the group's core:

| Key | Default | Meaning |
|---|---|---|
| `cmc:memberAccess:defaultTtl` | `86400` | Expiry, in seconds, of a member access asked without `expireAfter`. |
| `cmc:memberAccess:minTtl` | `60` | Shortest `expireAfter` accepted. |
| `cmc:memberAccess:maxTtl` | `604800` | Longest `expireAfter` accepted; also the longest a residual can last. |
| `cmc:memberAccess:ratePerMinute` | `30` | Requests per membership per minute, per server process. |
| `cmc:memberAccess:maxInFlightPerMembership` | `1` | Requests in flight per membership and patient, per server process. |
| `cmc:memberAccess:allowNameOnly` | `true` | Fall back to name-only attribution against an older patient core. |
| `cmc:memberAccess:sweepIntervalMs` | `60000` | Interval of the periodic ledger pass (expired and vanished memberships, residuals re-swept), which runs with the retry loop. |
| `cmc:retryLoop:enabled` | `true` | The CMC retry loop. |

**The retry loop is on by default from open-pryv.io 2.0.0-rc.53**, on every core. It carries the sweep retries, the periodic ledger pass and the re-sending of revoke notices. An account with nothing pending or open in either pass is checked again only after 10 minutes instead of every interval, so new work on a dormant account can wait up to 10 minutes. Set to `false`, nothing is queued, a warning is logged at boot, a residual lasts until the access expires, and a revoke notice the other core could not take is not sent again.

**A core that ran with the loop off** (the previous default) still holds the failures of that time in each account's retry queue. When the loop starts, a pending record older than its whole schedule (2 hours for a request, 30 hours for a revoke notice) is retired as `failed-permanent` with `lastFailureReason: 'cmc-retry-stale'` and never sent, so nothing that old reaches another core. Records that succeeded are pruned at once, `failed-permanent` ones after 30 days.

## Walkthrough with `@pryv/cmc`

The helpers are in [`@pryv/cmc`](https://www.npmjs.com/package/@pryv/cmc) 3.21.0 and later, beside `pryv`. For a complete static member app built on them (join a group, invite patients, open a patient's data), see the reference app [app-web-group-member](https://github.com/pryv/app-web-group-member).

### Group setup (owner)

```js
const pryv = require('pryv');
const cmc = require('@pryv/cmc');

const owner = new pryv.Connection(groupOwnerApiEndpoint);   // personal token
await owner.api([
  { method: 'streams.create', params: { id: ':_cmc:apps:practice', parentId: ':_cmc:apps', name: 'Practice' } },
  { method: 'streams.create', params: { id: ':_cmc:apps:practice:team-a', parentId: ':_cmc:apps:practice', name: 'Team A' } }
]);
```

### Member side

The member's app signs in to the member's own account with `read` on `:_cmc:inbox` and `contribute` on the app's scope (`:_cmc:apps:practice`, created as in the [CMC guide](/guides/cross-account-messaging/#the-handshake--a-worked-example)).

```js
const member = new pryv.Connection(memberApiEndpoint);   // the member's own account
const group = { username: 'practice', host: 'pryv.example' };

// 1. Ask to join, then show request.capabilityUrl as a QR code or a link.
const request = await cmc.requestMembership(member, {
  group,
  scopeStreamIds: [':_cmc:apps:practice:team-a'],   // team streams on the GROUP's account
  appCode: 'practice',
  displayName: 'Dr. Who'                            // how the administrator sees the member
});

// 2. Wait for an administrator (a person: use a long timeout, or call again later).
const joined = await cmc.waitForMembership(member, { group, appCode: 'practice', timeoutMs: 10 * 60 * 1000 });
const membership = new pryv.Connection(joined.membershipApiEndpoint);   // the membership on the group's account

// 3. Invite a patient for the group: a delegable grant.
const invite = await cmc.createInvite(membership, {
  appCode: 'practice',
  scopeStreamId: ':_cmc:apps:practice:team-a',
  displayName: 'Practice',
  requestedPermissions: [{ streamId: 'diary', level: 'read' }],
  accessType: 'app'
});
// Hand invite.capabilityUrl to the patient.

// 4. Once the patient accepted, open their data.
// The invite record's counterparty is who answered it: check the status, as it is also set on a refusal.
const record = await cmc.getInviteStatus(membership, invite.inviteEventId);
if ((record.status === 'accepted' || record.status === 'completed') && record.counterparty) {
  try {
    const access = await cmc.requestMemberAccess(membership, {
      counterparty: { username: record.counterparty.username, host: record.counterparty.host },
      scopeStreamId: ':_cmc:apps:practice:team-a',
      expireAfter: 3600
    });
    const patient = new pryv.Connection(access.apiEndpoint);   // do not log or store
    const { events } = await patient.get('events', { streams: ['diary'], limit: 20 });
  } catch (err) {
    if (cmc.isMemberAccessRetryable(err)) { /* in flight, or the patient's core unreachable: ask again shortly */ }
    // Otherwise err.id is one of cmc.errorIds.MEMBER_ACCESS_* (see below).
  }
}

// 5. Leave the group: the group's core then deletes the accesses it created for this member.
await cmc.leaveMembership(member, { inviteEventId: request.inviteEventId });
```

`requestMembership` checks the team streams before writing, as the server does, and sends `features` as `{ chat: false, systemMessaging: true }`. `waitForMembership` counts only an accept from `group`. `leaveMembership` before the administrator accepted throws `cmc-capability-invalid`: there is nothing to leave, and the request simply expires.

### Administrator side

With the group's personal token, or a delegate's token for the group account:

```js
const admin = new pryv.Connection(groupAdminApiEndpoint);

// Read the pasted or scanned URL: offer.membership is true, offer.requester is the member,
// offer.requestedPermissions lists the teams asked for (show them as checkboxes).
const offer = await cmc.readOffer(pastedOrScannedUrl);

const accepted = await cmc.acceptMembership(admin, pastedOrScannedUrl, {
  scopeStreamId: ':_cmc:apps:practice',            // the group's stream where the accept is written
  grantedScopes: [':_cmc:apps:practice:team-a']    // optional: a subset of the requested teams
});
// accepted = { acceptEventId, membershipAccessId, member }
// An ordinary invite, not a membership request, throws cmc-membership-offer-expected.

// Or decline it:
// await cmc.declineMembership(admin, pastedOrScannedUrl, { scopeStreamId: ':_cmc:apps:practice' });

// List the members: identity, teams, who approved. No credentials.
const members = await cmc.listMembers(admin);

// Offboard one member, then check the sweep.
await cmc.revokeMembership(admin, {
  membershipAccessId: members[0].membershipAccessId,
  scopeStreamId: members[0].scopeStreamId
});
const { items } = await cmc.listSweeps(admin, { membershipAccessId: members[0].membershipAccessId });
const sweep = await cmc.getSweepStatus(admin, items[0].sweepEventId);
// sweep.status: 'pending' | 'delivered' | 'completed' | 'failed'
// sweep.outcome: [{ childAccessId, result: 'deleted' | 'absent' | 'residual' }]
// sweep.residuals: [{ counterparty, childAccessId, expires, reason }]
```

## Error ids

Refused when the request is written (`error.data.id`, thrown by `@pryv/cmc` as a `CmcError`):

| Id | Meaning |
|---|---|
| `cmc-member-access-not-member` | The event was not written with a membership (personal and delegate tokens are refused too). |
| `cmc-member-access-relationship-not-found` | No relationship with this patient under the stream, or its handshake is not complete, or the group's invite to the patient can no longer be read (`error.data.reason: 'offer-not-found'`): invite the patient again. |
| `cmc-member-access-scope-outside-membership` | The patient's relationship is not under the stream the event was written on, or the event is not on a team stream. |
| `cmc-member-access-permissions-not-subset` | Not stream permissions, or beyond what the group's invite offered the patient. |
| `cmc-member-access-expiry-out-of-range` | `expireAfter` outside the core's bounds, or less than the minimum left on the membership. |
| `cmc-member-access-rate-limited` | Too many requests for this membership: ask again after the minute. |
| `cmc-member-access-in-flight` | A request for this membership and this patient is already running: ask again shortly. |
| `cmc-membership-permissions-invalid` | A membership request breaks the membership rules (also recorded on the accept when the group's core refuses it, or when a delegate administrator approves their own membership). |
| `cmc-member-stamp-invalid` | The patient's core refused a malformed member stamp. |

Recorded on the event (`content.failure.reason`):

| Id | Meaning |
|---|---|
| `cmc-member-access-grant-not-delegable` | The patient's grant is `shared`: invite the patient again with `accessType: 'app'`. |
| `cmc-member-access-permissions-not-subset` | The patient's core refused the access as beyond the grant. |
| `cmc-member-access-peer-rejected` | The patient's core refused the access otherwise (its error id and HTTP status in `content.failure.detail`). |
| `cmc-member-access-peer-unreachable` | The patient's core could not be reached: ask again shortly. |
| `cmc-member-access-membership-gone` | The membership ended while the access was being created; the access was deleted. |
| `cmc-member-access-not-retryable` | A request for a member access is never replayed from the retry queue. |
| `cmc-member-revoke-residual` | A sweep left accesses in place (see `residuals`). |
| `cmc-member-channel-not-supported` | A chat the group addressed to a member. A chat, alert or ack written through a membership is refused at write with the same id (403). |

Other CMC ids met on group accounts: `cmc-protected-event-write` (403: a client wrote a `consent/member-revoke-cmc`, or an app or shared access, a membership included, tried to update or delete a member record), `cmc-accept-requires-personal-token` (a membership tried to accept), `cmc-invalid-event-content` and `cmc-offer-stream-not-offerable` (an offer asked for a stream the plugin manages, see [The trust boundary](#the-trust-boundary)), and `cmc-invalidate-link-scope-mismatch` (an invite closed from another stream, see [Inviting a patient](#inviting-a-patient)).

Produced by `@pryv/cmc` only: `cmc-member-access-unsupported` (the group's core does not support member accesses), `cmc-member-access-token-missing` (the access was created but the answer arrived without it: ask again) and `cmc-membership-offer-expected` (`acceptMembership` given an ordinary invite).

## The alternative: one access and a caller label

When the group runs its own server, it can keep the plain CMC model: one relationship per patient, an ordinary `shared` grant, held by the server and never sent to members' browsers. The server authenticates its staff itself and, on each call to the patient's core, sends the staff member's identifier as a **caller id** after the token, separated by a space:

```
Authorization: <grant token> <caller id>
```

The patient's core records the `callerId` on each audit entry, and app-web-user-account, from its next release, shows it as "Caller label (not verified)". The label is whatever the caller sends: anyone holding the token can send any label. It becomes a verified identity only where the patient's platform runs a [custom auth step](/guides/custom-auth/) that checks it, which is a decision of the patient platform's operator, not of the group.

Offboarding a staff member is then the server's job: it stops serving them. Nothing changes on the patient side, and a staff member who copied the token keeps the group's access until the patient or the group revokes the grant.

## Further reading

- [Cross-account Messaging & Consent (CMC)](/guides/cross-account-messaging/): the handshake, scope streams, delegable grants and revocation.
- [Account delegation](/guides/account-delegation/): delegates as group administrators, and what removing one does.
- [Custom authentication](/guides/custom-auth/): verifying a caller id on the patient's platform.
- [Audit logs](/guides/audit-logs/): what each call records.
- [`@pryv/cmc` README](https://github.com/pryv/lib-js/tree/master/components/pryv-cmc): the full client surface.
- [app-web-group-member](https://github.com/pryv/app-web-group-member): the reference member app, a static web app with no backend.
