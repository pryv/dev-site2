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

## OpenAPI definitions

`openapi.ts` turns this dataset into OpenAPI 3.0.3 documents; the build serves them at
`/open-api/3.0/api.yaml` (user API; `api_open.yaml` is a byte-identical legacy alias) and
`/open-api/3.0/api_system.yaml` (system API), rendered by the endpoints under
`src/pages/open-api/3.0/`. Nothing is committed and nothing is hand-edited: change the
reference source, and the definitions follow at the next build. The admin reference is not
published as OpenAPI.

- Every property `type` string must be in the generator's explicit type table; an unknown
  string throws. When the reference gains a new type string, add its mapping there.
- `npm run gate:openapi` validates both documents (OpenAPI schema, dangling `$ref`), checks
  that every documented method appears exactly once (`x-pryv-method-ids`) and that no
  admin-only method does, and that `info.version` is the reference version.
  `npm run gate:openapi:dist` also checks the built `dist/open-api/3.0/` files against a
  fresh generation. CI runs both gates; `just publish` runs them before pushing.

## Anchors

Two anchor systems are reproduced for stable deep links: the hierarchical section id
(`methods-auth-auth-login`) on the wrapping `<section>`, and the heading text-slug on each
`<h2>`..`<h6>`. Cross-references embedded in descriptions (`#data-structure-event`, …) rely
on the section ids, so those ids are stable and must not change.
