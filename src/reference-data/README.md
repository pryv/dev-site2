# Reference data

`reference.json` is the API reference dataset: the single source consumed by both the
reference pages and the OpenAPI generator. `types.ts` describes its shape and `index.ts`
exposes a typed surface (`apiReference`, `version`, `userSections`, `systemSection`,
`adminSection`).

## Shape

`{ sections, version, system, admin }`. `sections` is the user API (basics, methods,
data structure); `system` and `admin` are the system and admin API surfaces. Every node
is a `Section`; a method is a `Section` with `type: "method"` carrying `http`, `server`,
`params`, `result`, `errors` and `examples`. See `types.ts`.

## Generation and determinism

`reference.json` is machine-generated from the CoffeeScript reference source in
[`../../reference-src/`](../../reference-src/), not hand-edited. That source was migrated
out of the now-archived legacy `dev-site` repo so the dataset is regenerable from within
this repo.

- Edit the source under `reference-src/` (`methods.coffee`, `system.coffee`, `admin.coffee`,
  `data-structure.coffee`, `basics.coffee`, and the `examples/` fixtures).
- Regenerate: `npm run gen:reference` (writes `src/reference-data/reference.json`).
- Verify: `npm run gate:reference` compares a fresh generation against the committed file
  byte for byte and exits non-zero on drift.

Example payloads use **frozen placeholder** identifiers, tokens and timestamps (the
generator pins cuid, `Date`, `Math.random` and `crypto.randomBytes`) so the output is
identical on every run and machine. `reference-src/` is scoped CommonJS via its own
`package.json` (the repo root is `type: module`).

## Anchors

Two anchor systems are reproduced for stable deep links: the hierarchical section id
(`methods-auth-auth-login`) on the wrapping `<section>`, and the heading text-slug on each
`<h2>`..`<h6>`. Cross-references embedded in descriptions (`#data-structure-event`, …) rely
on the section ids, so those ids are stable and must not change.
