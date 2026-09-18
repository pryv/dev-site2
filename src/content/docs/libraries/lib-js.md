---
title: 'lib-js: the JavaScript client'
description: Overview of the official Pryv.io JavaScript/TypeScript client library (the `pryv` npm package) for Node.js and the browser, with links to the full docs.
---

`lib-js` is the official Pryv.io client library for **JavaScript / TypeScript**, published
on npm as [`pryv`](https://www.npmjs.com/package/pryv). It works both in **Node.js** and
in the **browser**, and wraps the [HTTP API](/reference/) with a small, promise-based
surface (connections, batched API calls, authentication helpers, high-frequency series,
and event/attachment helpers).

## When to use it

Reach for `lib-js` when you build a JavaScript or TypeScript app or service that talks to
a Pryv.io account, instead of calling the [REST API](/reference/) by hand. For other
languages, use the [OpenAPI definitions](/open-api/) to generate a client, or call the
API directly.

## Install

```bash
npm install pryv
```

## Minimal example

```js
const Pryv = require('pryv');

// An API endpoint is `https://{token}@{username}.{domain}/`
const connection = new Pryv.Connection('https://TOKEN@USERNAME.pryv.me');

// Batched API calls use the same method ids as the reference
const [result] = await connection.api([
  { method: 'events.get', params: { limit: 20 } },
]);

console.log(result.events);
```

In the browser, the same library is available as a bundle; see the repository for the
script-tag and authentication (auth request) flows.

## Sign-in button

In the browser, `pryv.Browser.setupAuth()` renders a sign-in button in the element named by
`spanButtonID`, runs the [auth request](/reference/#auth-request) when it is clicked, and
keeps the signed-in state in a cookie so it survives a reload.

```js
const service = await pryv.Browser.setupAuth({
  spanButtonID: 'pryv-button',
  authRequest: {
    requestingAppId: 'my-app',
    requestedPermissions: [{ streamId: 'diary', defaultName: 'Journal', level: 'read' }]
  },
  onStateChange: async (state) => {
    if (state.status === 'ACCEPTED' && state.key != null) {
      const connection = await pryv.connectFromKey(state.key, serviceInfoUrl);
    }
  }
}, serviceInfoUrl);
```

### Account menu

From lib-js 3.13, clicking the button while signed in opens a small **account menu**
instead of asking to log out. It shows the signed-in username, the service name and the
app id, and two actions:

- **Manage my account** opens the platform's account app (its profile page) in a new tab.
  The entry is hidden when no account app URL can be found (see below).
- **Log out** forgets the stored credentials. `SIGNOUT` reaches `onStateChange` when
  "Log out" is chosen (no longer on the click itself), then the button returns to its
  signed-out state.

The menu is a modal dialog: Escape, the close button or a click outside it close it, and
the keyboard focus stays inside while it is open. Its style uses the `.pryv-menu*` classes,
which a service's button stylesheet can override; its labels (`MENU_TITLE`, `LOGOUT`,
`MANAGE_ACCOUNT`, `APP`, `CLOSE`, `CANCEL`, in English and French) can be overridden by
the service's button messages, key by key.

Settings (beside `spanButtonID` and `authRequest`):

| Setting | Effect |
| --- | --- |
| `menu: false` | No menu: the click emits `SIGNOUT` and asks "Log out?" in a built-in dialog (the previous behaviour, without the browser's native `confirm()`). Cancelling it restores the signed-in state from the stored credentials: listeners see `LOADING`, then `ACCEPTED`. |
| `menu: { account: false }` or `menu: { hide: ['account'] }` | Hides an entry. The entries are `logout`, `account` and `info` (the service and app line). |
| `accountUrl` | Root URL of the account app, overriding discovery. |

**Where "Manage my account" points.** The button uses the first available of:

1. the `accountUrl` setting;
2. the `account` field of the [service information](/reference/#service-info);
3. the auth page URL of the sign-in (the `authUrl` of the auth request, kept with the
   stored credentials) with its trailing `/auth` removed, since the platform's account app
   serves its auth page at `/auth`;
4. none: the entry is hidden.

It opens `{root}/account/profile?pryvServiceInfoUrl={serviceInfoUrl}`.

### Controller methods

The `AuthController` (`button.auth` on the built-in `pryv.Browser.LoginButton`, or the
controller your own button creates) offers:

- `signOut()`: a confirmed logout. Emits `SIGNOUT` once, clears the stored credentials and
  re-initializes the controller.
- `accountUrl()`: the account app's profile URL described above, or `null`.
- `openAccountApp()`: opens that URL in a new tab and returns it, or returns `null`.

### Custom buttons

A custom button (the fourth argument of `setupAuth`) may implement an optional
`showMenu()`. When the signed-in button is clicked, the controller calls it; your button
opens its own menu and logs out with `auth.signOut()`. Returning `false` (or not
implementing `showMenu()`) keeps the previous contract: the controller emits `SIGNOUT` and
your button handles the logout itself.

<!-- Switching between accounts from the menu is documented here once released. -->

## Full documentation

The authoritative documentation, browser usage, authentication flows, high-frequency
series and the complete API live in the repository:

- **Repository**: [github.com/pryv/lib-js](https://github.com/pryv/lib-js)
- **npm**: [`pryv`](https://www.npmjs.com/package/pryv)

See also [Get started](/getting-started/) and the [API reference](/reference/).
