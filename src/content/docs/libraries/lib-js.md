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

## Full documentation

The authoritative documentation, browser usage, authentication flows, high-frequency
series and the complete API live in the repository:

- **Repository**: [github.com/pryv/lib-js](https://github.com/pryv/lib-js)
- **npm**: [`pryv`](https://www.npmjs.com/package/pryv)

See also [Get started](/getting-started/) and the [API reference](/reference/).
