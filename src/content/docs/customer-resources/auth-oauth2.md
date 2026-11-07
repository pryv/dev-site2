---
title: 'Pryv.io OAuth2 app authorization'
description: How Pryv.io apps obtain access to a user account, comparing the native access-request polling flow with the built-in OAuth2 authorization-code flow.
---


This document is for **app developers** choosing how their application obtains access to a Pryv.io user account, and for **platform operators** deciding whether to enable the OAuth2 layer. Pryv.io v2 supports two app-authorization flows side by side:

- the **Pryv-native access-request polling flow** (`/reg/access` — see [Authenticate your app](/reference/#authenticate-your-app)), and
- a standard **OAuth2 authorization-code flow** (RFC 6749 + PKCE / RFC 7636) served by the core itself.

Neither flow is deprecated. Pick per app using the decision matrix below.

## Which flow should my app use?

| Your situation | Recommended flow |
|---|---|
| Self-hosted webapp with its own login UI, tightly integrated with one Pryv.io platform | **Access-request polling** (`/reg/access`) — no client registration needed, works with the stock auth pages |
| SaaS product serving many users, possibly across platforms | **OAuth2** — standard redirect flow, refresh tokens, revocable app accounts |
| Third-party SDK / integration built on a generic OAuth2 client library | **OAuth2** — any RFC 6749-compliant library works against the discovery document |
| Device or CLI without a browser | **Access-request polling** (display the URL / QR, poll for approval) |
| Server-to-server access under an application identity (no end user in the loop) | **OAuth2 `client_credentials`** grant |

Both flows end in the same thing: a Pryv.io **app access** whose token authenticates API calls. The difference is how the token is obtained and how its lifetime is managed.

## The OAuth2 flow at a glance

1. Your app redirects the user's browser to `GET /oauth2/authorize` with `client_id`, `redirect_uri`, `scope`, `state`, and a PKCE `code_challenge` (S256 — mandatory for every authorization-code request, public and confidential clients alike). Generate `state` as an unguessable random value and remember it for step 3.
2. The user signs in and reviews the consent screen, which lists every permission your consent offer asks for (see [Scopes](#scopes)); the user may untick individual permissions — you receive only the kept subset.
3. The browser is redirected back to your registered `redirect_uri` with an authorization `code` and your `state`. **Verify the returned `state` matches the value you sent** before proceeding — this is your CSRF protection. The response also carries `iss` (RFC 9207); if your library supports it, confirm it equals the discovery document's issuer to guard against mix-up attacks.
4. Your app exchanges the code at `POST /oauth2/token` (with the PKCE `code_verifier`) and receives the token response.
5. API calls carry the access token as `Authorization: Bearer <token>`.

The token response is the standard RFC 6749 §5.1 JSON plus a Pryv extension field:

```json
{
  "access_token": "...",
  "token_type": "Bearer",
  "expires_in": 3600,
  "refresh_token": "...",
  "scope": "cmc:study-A",
  "apiEndpoint": "https://{token}@{host}/{path}/"
}
```

## Endpoints and discovery

Each deployment publishes an RFC 8414 discovery document at:

```
GET https://<deployment-base>/.well-known/oauth-authorization-server
```

It advertises `authorization_endpoint`, `token_endpoint`, `scopes_supported`, `code_challenge_methods_supported` (`["S256"]`) and the supported grant types, and since 2.0.0-rc.69 `introspection_endpoint` (`POST /oauth2/introspect`, RFC 7662, for confidential clients the operator allowed to introspect) and `revocation_endpoint` (`POST /oauth2/revoke`, RFC 7009). Point any generic OAuth2 client library at this document instead of hardcoding endpoint URLs.

The issuer is the core's own URL unless the operator sets `oauth.issuer` (for instance a vanity host such as `https://auth-eu.<domain>`); the discovery document always names the configured issuer. Operators: see "`issuer` (optional)" in the [OAuth2 operator guide](https://github.com/pryv/open-pryv.io/blob/master/docs/oauth2.md).

## Scopes

There are no coarse wildcard scopes: every grant is an explicit, granular permission set — the same expressiveness as a native `accesses.create` permissions array, including per-stream levels (`read`, `contribute`, `manage`, `create-only`) and feature permissions such as `{"feature": "selfRevoke", "setting": "forbidden"}`.

The `scope` parameter carries exactly **one consent-offer reference**: `scope=cmc:<offer-name>`. The offer is a cross-account consent request your app account publishes once (with the permission list and the consent texts shown to the user); the platform operator registers it on your OAuth client under `<offer-name>`. At authorization time the server resolves the offer and the consent screen displays each permission.

This section describes clients backed by an app account. A platform may also register **registry clients**, whose scope vocabulary comes from an OAuth extension the operator installs; their scopes, consent screen (composed with what the user already granted, where unticking narrows the grant when the screen shows the composed offer) and token `scope` follow that extension: see the [OAuth2 operator guide](https://github.com/pryv/open-pryv.io/blob/master/docs/oauth2.md) and the platform's own documentation.

**All-or-nothing by default.** Unless the offer sets `allowUserChoice: true`, the consent is take-it-or-leave-it: the user accepts the whole permission set or denies (no cherry-picking). Set `allowUserChoice: true` in your offer to let the user untick individual permissions — and flag any entry your app cannot run without as `mandatory: true` so it stays locked (the user's only way to withhold it is to deny the whole request). The minted access always carries **exactly the granted subset**, so always read the effective grant (see below) rather than assuming the full offer.

**How each entry opens.** Once the offer allows user choice, an entry can also carry `optIn: true`, which makes the consent screen present it **unticked**, so the user has to choose it. The three states are:

| Entry carries | The user sees |
|---|---|
| `mandatory: true` | ticked and locked, with a "required by this app" note |
| neither flag | ticked, and they may untick it |
| `optIn: true` | unticked, and they may tick it |

`optIn` is display-only: it decides how the screen opens, never what may be granted, so an opt-in entry the user leaves unticked is simply absent from the grant. An entry may not carry both flags. A forbidden feature (`{ "feature": …, "setting": "forbidden" }`) is a restriction on your app, not a permission: since 2.0.0-rc.68 it is always mandatory, and an offer marking one `optIn` is refused. Where consent is your lawful basis under the GDPR, prefer `optIn`: [Recital 32](https://gdpr.eu/recital-32-conditions-for-consent/) states that pre-ticked boxes do not constitute consent.

Two consequences worth designing for:

- **The grant is a durable consent on the user's account.** The user can revoke it (or narrow it) at any time from their account tooling; revocation makes your next token refresh fail with `invalid_grant` (re-run the authorization flow), and narrowing reaches your live access tokens at once (since 2.0.0-rc.68; earlier releases applied it at the next refresh). Revocation targets the durable consent (the data-grant): deleting it breaks the refresh chain and, since 2.0.0-rc.64, deletes the live session accesses minted from it too, so account tooling and UIs should revoke the data-grant rather than rely on any single access token expiring. Since 2.0.0-rc.66 a refresh keeps, stream by stream, what both your consent and the current grant allow: a stream the user narrowed is kept at the narrowed level, an exclusion the user added below a stream you hold (a child stream at `none` or `create-only`) and a feature restriction added to the grant reach the refreshed access, and a refresh left with no stream fails with `invalid_grant`. Since 2.0.0-rc.68 the access minted at consent also starts under the grant's restrictions, and when the grant changes (the user narrows it, a re-consent, a consent scope update) each live access token of your app is brought at once to what its next refresh would mint; one left with no stream is deleted, and its refresh then fails with `invalid_grant` unless the user widened the grant again meanwhile.
- **Re-authorizing merges per stream.** When the user consents again to an app that already holds a grant, the new consent is joined into the grant stream by stream (a stream at `read` consented again at `contribute` holds `contribute`). A consent combining `read` and `create-only` on one stream is refused with `400 invalid_scope`: no level grants exactly both, so ask for `contribute` if your app needs both.
- **Always read the effective grant, not the requested one** — call `GET /access-info` with the access token to see the exact permissions you hold.

## Multi-core deployments: the `apiEndpoint` extension

On a multi-core platform, each user's data lives on one specific core. The `/oauth2/*` endpoints are available on every core, but **API calls must target the user's own core**.

- **Clients SHOULD read the `apiEndpoint` field from the token response** and use it as the base for all subsequent API calls. It already points at the right core (and embeds the token in Pryv's standard [API endpoint format](/reference/#api-endpoint)).
- **Pseudonymous grants** (a registry client with `pairwise` subjects, or an offer asking for a pseudonym; since 2.0.0-rc.69) get no `apiEndpoint`: the app knows the account by an alias only, given as the token's subject and in `access-info`, and the token is accepted at that alias only.
- **Vanilla RFC 6749 clients** that ignore `apiEndpoint` and call an arbitrary core will receive **HTTP `421 Misdirected Request`** with an error body containing `coreUrl` — the base URL of the user's core. Retry the same request against `coreUrl`.
- **Consent UIs**: when the signed-in account is served by another core than the one that issued the authorization (the app used another region's address), the signed-in `/oauth2/authorize/offer` and `/oauth2/authorize/accept` answer `421 { "error": "wrong_core", "error_description", "coreUrl" }` (from open-pryv.io 2.0.0-rc.74). The flow cannot move to that core: end it with a message (the host of `coreUrl` may be shown) and a way back to the app (`/oauth2/authorize/refuse`); do not send the user back to the sign-in.

```json
{
  "error": {
    "id": "wrong-core",
    "message": "User \"alice\" is hosted on a different core. Retry the request against the URL in `coreUrl`.",
    "coreUrl": "https://core-b.example.com"
  }
}
```

[lib-js](https://github.com/pryv/lib-js) handles this automatically.

## Token lifetimes and refresh

Unlike Pryv-native app tokens (long-lived until revoked or expired via `expireAfter`), OAuth2 access tokens are **short-lived** (1 hour by default) and come with a **refresh token** (30-day sliding window, 90-day absolute cap, by default — operators can tune all three). Refresh with:

```
POST /oauth2/token
grant_type=refresh_token&refresh_token=...&client_id=...
```

Each refresh rotates the refresh token; the response carries a new access token, a new refresh token and the `apiEndpoint` (not for a pseudonymous grant). Since 2.0.0-rc.69 the access token a refresh replaces expires 60 seconds later (operator setting `oauth.refreshRetireGraceSeconds`), so switch to the new one at once. To sign out, revoke either token at `POST /oauth2/revoke`: it ends that refresh chain only (other devices and the user's consent stay). See [access tokens](/concepts/#accesses) for how this relates to the general access model.

## Token exchange for resource servers

From open-pryv.io 2.0.0-rc.73, a **resource server** in front of a core (an API facade, an agent gateway) can trade the access token a user's client sent it for a session of its own on the user's core (OAuth 2.0 Token Exchange, RFC 8693), then call the data API with that derived token. The user's authorization named the resource server (`aud` / `resource`) when the client obtained its token.

The resource server is a registry client the operator registers with `--can-exchange` (confidential, with an audience list). It posts to the token endpoint with its own client authentication:

```
POST /oauth2/token
grant_type=urn:ietf:params:oauth:grant-type:token-exchange
&subject_token=<the access token the client sent>
&subject_token_type=urn:ietf:params:oauth:token-type:access_token
```

The answer carries `access_token`, `issued_token_type`, `token_type: Bearer`, `expires_in`, `scope` and `api_base` (the account's API base URL), no refresh token. The derived session has the client's permissions, lives no longer than the client's session, ends when that session is deleted or the grant withdrawn, and a repeated exchange of the same subject token answers the same token while it lives. An unusable subject token answers `invalid_grant`; a subject session living on another core answers `421 wrong_core` with its `coreUrl`.

Operators: advertise the grant by adding `urn:ietf:params:oauth:grant-type:token-exchange` to `oauth.grantTypesSupported`. With `oauth.audienceBoundSessions: true`, the data API refuses the client's own token for a resource server (it then works only through that resource server's exchange); it is `false` by default in 2.0.0-rc.73 and **a later release is planned to default it to `true`**. Full rules, errors and lifecycle: [OAuth2 operator guide, § 1e](https://github.com/pryv/open-pryv.io/blob/master/docs/oauth2.md#1e-token-exchange-rfc-8693-for-resource-servers).

From 2.0.0-rc.75 the resource server may also send `subject_token_resource`, the resource URL at which it received the subject token: it must be the token's audience (`400 invalid_target`, "the subject token was not issued for the resource it was presented at"), so a token issued for one account's address is not exchanged when presented at another's. `resource` / `audience` keep naming the resource server itself.

## Per-user resource addresses

From open-pryv.io 2.0.0-rc.75, a resource server (an API facade, an agent gateway, an adapter) can be addressed at each account's own host. An `allowedAudiences` entry of a client (a registry client's `--audience`, or the metadata-document template's `client.allowedAudiences`) may be written `https://{username}.<host>[:port][/path][?query]`: exactly one `{username}`, as the first host label.

- **Matching.** A requested `aud` / `resource` matches such an entry when its first host label has the shape of an account name; the address is stored with that label as any audience. Exact entries keep working beside it and are matched first.
- **Bound at consent.** The signed-in `/oauth2/authorize/offer` and `/oauth2/authorize/accept` accept the address only when its label is the signed-in account's current username and not a name the platform answers itself (a service host, a core id, a static DNS entry, an OAuth issuer label, a hosted site): otherwise `403 { "error": "access_denied", "reason": "audience-account-mismatch" }`, before anything is written. A former username is refused for a new authorization; existing authorizations keep their address after a username change.
- **Client list changed.** An authorization whose audience the client's list no longer holds (or whose client is gone) answers `400 invalid_target`, `reason: "audience-not-listed"`: restart the flow.
- **Token exchange.** A subject token issued for such an address is exchanged when the resource server lists the matching entry; on the home core the address must name the subject account.
- **The account moved, or the request reached the wrong core:** on the host of an account another core serves, `/oauth2/token` answers `421 { "error": "wrong_core", "error_description", "coreUrl" }` with `Retry-After` before any code or refresh token is read, and `/oauth2/authorize` answers `421` with a static "this address has just moved" page. Retry the same address after the delay.

Operators: add a per-user entry only once every core of the platform runs 2.0.0-rc.75 (an older core matches it to nothing); the entry is the same on every core. Full rules: [OAuth2 operator guide, § 1c, resource indicators](https://github.com/pryv/open-pryv.io/blob/master/docs/oauth2.md#resource-indicators-aud--resource).

## Client metadata documents

From open-pryv.io 2.0.0-rc.74, a client can name itself, as its `client_id`, by the https URL of a JSON document it publishes (a **client metadata document**, RFC 7591 member names), instead of being registered by the operator. The platform must turn the feature on (`oauth.clientMetadataDocuments.mode: allowList` or `any`); the discovery documents then advertise `client_id_metadata_document_supported: true`.

```json
{
  "client_id": "https://app.example.com/oauth/client.json",
  "client_name": "Example app",
  "redirect_uris": ["https://app.example.com/callback"],
  "token_endpoint_auth_method": "none"
}
```

- **The URL** is an absolute `https:` URL with a path other than `/`, a host name (no IP address, not a host of the platform itself), written exactly as the URL standard serialises it (lower-case host, no `:443`): it is compared as a string, so two spellings are two clients. `client_id` in the document must be exactly that URL.
- **Redirect URIs** are `https`, or plain `http` on a loopback host only.
- **Public or confidential.** `token_endpoint_auth_method: none` (the default) makes a public client: PKCE (S256) on the code flow, no credential. `private_key_jwt` with a `jwks_uri` on the document's own host (or an inline `jwks`) makes a confidential client: it authenticates at `/oauth2/token` and `/oauth2/revoke` with a client assertion whose `iss` and `sub` are the document URL, signed with `ES256`, `ES384`, `RS256` or `RS384`.
- **What the client may be granted** comes from the platform's template, never from the document (a `scope` member is ignored). Such a client gets no introspection and no token exchange.
- **The fetch:** https only, no redirect followed, private addresses refused, `application/json` (or an `application/*+json` type), 16 KiB at most, 5 s. The document is cached (one hour by default); a changed document is taken at the next authorization after that.
- **Consent screen:** the offer carries `client.origin: "metadata-document"`, `client.metadataUrl` and `client.metadataHost`. A consent UI must show the host next to the client's name, never the name alone. The grant and its sessions carry `clientData.oauth.client` (`{ name?, host, url }`), which an account app uses to name the connected app.
- **Errors** at `/oauth2/authorize` are HTML 400 pages ("client metadata document invalid", "client metadata document unavailable, retry later"). Operators read the reason with `bin/oauth-client.js check-metadata <url>`, which fetches and checks a document without writing anything.

Operators: the configuration (`allowList` with `allowedHosts` is the cautious setting; `deniedHosts`; the fetch and row budgets; the `client` template, which `bin/oauth-client.js template-from <clientId>` prints from an existing registry client) is in the [OAuth2 operator guide, § 1f and § 2](https://github.com/pryv/open-pryv.io/blob/master/docs/oauth2.md#1f-client-metadata-documents-an-https-url-as-client_id). A `revoke` of such a client voids every code, refresh token, session and consent issued before it; the next authorization naming the URL creates the client again, with a new consent, unless its host is denied.

## Client registration

App accounts are **curated**: an operator registers your application on the platform (dynamic client registration is not offered; on a platform that accepts them, a [client metadata document](#client-metadata-documents) can stand in for a registration). To get a `client_id`, redirect URIs and (for confidential clients) a `client_secret`, contact the operator of the platform you are integrating with. Redirect URIs are matched **exactly**, with one carve-out (RFC 8252 § 7.3): on plain `http`, the loopback hosts `127.0.0.1`, `[::1]` and `localhost` (the latter since 2.0.0-rc.71) may vary the port, so a native or CLI app listening on an ephemeral port registers `http://127.0.0.1/callback`, `http://[::1]/callback` or `http://localhost/callback`. The three host forms are not interchangeable: register each loopback form your client may send.

Operators: registration and rotation are done with the `bin/oauth-client.js` CLI — see the [OAuth2 operator guide](https://github.com/pryv/open-pryv.io/blob/master/docs/oauth2.md).

## Using lib-js

The [`pryv` JavaScript library](https://github.com/pryv/lib-js) ships an `OAuth2Client` that wraps the whole browser flow — discovery, PKCE, redirect, callback handling, refresh — and returns a ready `pryv.Connection`:

```javascript
const client = new pryv.OAuth2Client({
  authorizationServer: 'https://core-euc1.pryv.me',
  clientId: 'my-app',
  redirectUri: 'https://my-app.example.com/callback',
  scope: 'cmc:study-A' // your registered consent-offer reference
});
// on your login page:
await client.redirectToAuthorize();
// on your callback page (pass the callback query string):
const connection = await client.handleCallback(window.location.search);
const info = await connection.get('access-info');
```

See the [lib-js README](https://github.com/pryv/lib-js#oauth2) for details.

## Related documents

- [Authenticate your app (access-request polling)](/reference/#authenticate-your-app)
- [API concepts — accesses](/concepts/#accesses)
- [OAuth2 operator guide (open-pryv.io)](https://github.com/pryv/open-pryv.io/blob/master/docs/oauth2.md)
