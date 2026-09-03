---
title: 'Apps & libs'
---


This page lists official libraries, as well as example code for you to develop your own Pryv.io apps.


## Web & Node.js

### JavaScript library
➔ [npm](https://www.npmjs.com/package/pryv), [GitHub](https://github.com/pryv/lib-js) (monorepo including add-ons)

Optional add-ons:
- **JS lib Socket.IO add-on** ➔ [npm](https://www.npmjs.com/package/@pryv/socket.io)
- **JS lib Monitor add-on** ➔ [npm](https://www.npmjs.com/package/@pryv/monitor)
- **JS lib CMC (Cross-account Messaging & Consent) add-on** ➔ [npm](https://www.npmjs.com/package/@pryv/cmc) — client-side helpers (slug builders, lifecycle wrappers, errorIds catalogue) for the CMC plugin shipped in Open Pryv.io v2. See the [CMC guide](/guides/cross-account-messaging/).

### Example web apps
➔ [GitHub](https://github.com/pryv/example-apps-web)

Implementing use cases such as:
- Collecting form data
- Viewing collected data and sharing it
- Collecting and consuming high-frequency data

### Auth web app
➔ [GitHub](https://github.com/pryv/app-web-user-account)

Handling registration, [auth requests](https://pryv.github.io/reference/#authenticate-your-app), password reset and email change

### Multi-Factor Authentication app
➔ [GitHub](https://github.com/pryv/app-web-mfa)

Handles the [MFA flow](https://pryv.github.io/reference/#multi-factor-authentication).


## iOS

### Swift library
➔ [GitHub](https://github.com/pryv/lib-swift)

### Swift example app
➔ [GitHub](https://github.com/pryv/example-app-ios)

### HealthKit integration (PoC)
➔ [GitHub](https://github.com/pryv/poc-integration-healthkit)


## Java

### Library
➔ [GitHub](https://github.com/pryv/lib-java)

### Java app examples
➔ [GitHub](https://github.com/pryv/example-apps-java)

### Android app example
➔ [GitHub](https://github.com/pryv/example-app-android)


## Other

### React-native example app
➔ [GitHub](https://github.com/pryv/example-app-react-native)

Based on the [JavaScript library](https://github.com/pryv/lib-js).

### Subject account backup — CLI + library + sample web app
➔ CLI + library: [pryv-account-backup](https://github.com/pryv/pryv-account-backup)
➔ Sample web app: [pryv-account-backup-webapp](https://github.com/pryv/pryv-account-backup-webapp)

A subject-facing tool for downloading every read-side resource of a Pryv account (account / streams / accesses + history / profile / audit log / events / attachments / HFS series / webhooks) as a portable JSON + binary disclosure bundle. Two flavors share the same library code:

- The **CLI** (`npm start`) is the canonical flavor; produces a folder of JSON + binary files plus a per-file sha256 integrity manifest for third-party auditors.
- The **sample web app** is operator-hosted so non-technical subjects can self-serve via a "Start backup" button; produces the same coverage as the CLI minus the auditor-facing manifest, emitted as a series of subject-portable ZIP files.

Subjects also get a portable `sync-state.json` they keep alongside the backup; re-supplying it on the next visit drives cross-session incremental, so subsequent runs only fetch what's changed.

The previous-generation [`pryv/example-service-bluebutton`](https://github.com/pryv/example-service-bluebutton) is archived; new deployments use the pair above.
