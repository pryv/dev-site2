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

`reference.json` is machine-generated from the canonical API definitions, not hand-edited.
Example payloads use **frozen placeholder** identifiers, tokens and timestamps so the
build is fully reproducible (identical output on every run). Regenerating the file must
keep it deterministic; a fidelity check compares a fresh generation against the committed
file byte for byte.

## Anchors

Two anchor systems are reproduced for stable deep links: the hierarchical section id
(`methods-auth-auth-login`) on the wrapping `<section>`, and the heading text-slug on each
`<h2>`..`<h6>`. Cross-references embedded in descriptions (`#data-structure-event`, …) rely
on the section ids, so those ids are stable and must not change.
