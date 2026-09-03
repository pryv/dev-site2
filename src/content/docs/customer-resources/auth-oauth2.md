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

It advertises `authorization_endpoint`, `token_endpoint`, `scopes_supported`, `code_challenge_methods_supported` (`["S256"]`) and the supported grant types. Point any generic OAuth2 client library at this document instead of hardcoding endpoint URLs.

## Scopes

There are no coarse wildcard scopes: every grant is an explicit, granular permission set — the same expressiveness as a native `accesses.create` permissions array, including per-stream levels (`read`, `contribute`, `manage`, `create-only`) and feature permissions such as `{"feature": "selfRevoke", "setting": "forbidden"}`.

The `scope` parameter carries exactly **one consent-offer reference**: `scope=cmc:<offer-name>`. The offer is a cross-account consent request your app account publishes once (with the permission list and the consent texts shown to the user); the platform operator registers it on your OAuth client under `<offer-name>`. At authorization time the server resolves the offer and the consent screen displays each permission.

**All-or-nothing by default.** Unless the offer sets `allowUserChoice: true`, the consent is take-it-or-leave-it: the user accepts the whole permission set or denies (no cherry-picking). Set `allowUserChoice: true` in your offer to let the user untick individual permissions — and flag any entry your app cannot run without as `mandatory: true` so it stays locked (the user's only way to withhold it is to deny the whole request). The minted access always carries **exactly the granted subset**, so always read the effective grant (see below) rather than assuming the full offer.

Two consequences worth designing for:

- **The grant is a durable consent on the user's account.** The user can revoke it (or narrow it) at any time from their account tooling; revocation makes your next token refresh fail with `invalid_grant` (re-run the authorization flow), and narrowing propagates to the next refreshed access. Revocation targets the durable consent (the data-grant): deleting it breaks the refresh chain, but a session access token already minted stays valid until its own short expiry (≤ 1 hour by default), so account tooling and UIs should revoke the data-grant rather than rely on any single access token expiring.
- **Always read the effective grant, not the requested one** — call `GET /access-info` with the access token to see the exact permissions you hold.

## Multi-core deployments: the `apiEndpoint` extension

On a multi-core platform, each user's data lives on one specific core. The `/oauth2/*` endpoints are available on every core, but **API calls must target the user's own core**.

- **Clients SHOULD read the `apiEndpoint` field from the token response** and use it as the base for all subsequent API calls. It already points at the right core (and embeds the token in Pryv's standard [API endpoint format](/reference/#api-endpoint)).
- **Vanilla RFC 6749 clients** that ignore `apiEndpoint` and call an arbitrary core will receive **HTTP `421 Misdirected Request`** with an error body containing `coreUrl` — the base URL of the user's core. Retry the same request against `coreUrl`.

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

Each refresh rotates the refresh token; the response carries a new access token, a new refresh token and the `apiEndpoint`. See [access tokens](/concepts/#accesses) for how this relates to the general access model.

## Client registration

App accounts are **curated**: an operator registers your application on the platform (dynamic client registration is not offered). To get a `client_id`, redirect URIs and — for confidential clients — a `client_secret`, contact the operator of the platform you are integrating with. Redirect URIs are matched **exactly** (RFC 8252; loopback `http://127.0.0.1` / `http://[::1]` redirect URIs may vary port).

Operators: registration and rotation are done with the `bin/oauth-client.js` CLI — see the [OAuth2 operator guide](https://github.com/pryv/open-pryv.io/blob/master/docs/oauth2.md).

## Using lib-js

The [`pryv` JavaScript library](https://github.com/pryv/lib-js) ships an `OAuth2Client` that wraps the whole browser flow — discovery, PKCE, redirect, callback handling, refresh — and returns a ready `pryv.Connection`:

```javascript
const client = new pryv.OAuth2Client({
  authorizationServer: 'https://demo.datasafe.dev',
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
