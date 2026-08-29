# Laws

*What must be true. Below the [principles](../principles.md), which decide why.*

A law is what a principle produces where it produces something checkable. Each file states
four things and stops:

- **what must be true**
- **the principle it serves** — and, where two produce it, which one governs on conflict
- **the guard** that holds it
- **the guard's limit** — what a passing run does not prove

> **Every guard here is specified, not built.** The cops arrive in phase 3. Until then
> every law on this list is a convention, held by review, and saying otherwise would be the
> exact failure `a-guard-states-its-limit` exists to prevent.

A law with no guard says so, permanently, and is called a convention. Calling it a law does
not make it hold.

## The list

| Law | Principle |
|---|---|
| [`one-operation-one-class`](one-operation-one-class.md) | `one-way-to-say-each-thing` |
| [`the-call-graph-is-declared`](the-call-graph-is-declared.md) | `good-boundaries-make-good-neighbours` |
| [`nothing-travels-off-the-call-path`](nothing-travels-off-the-call-path.md) | `good-boundaries-make-good-neighbours` |
| [`arguments-are-typed-at-construction`](arguments-are-typed-at-construction.md) | `nothing-crosses-unasserted` |
| [`input-is-parsed-at-the-seam`](input-is-parsed-at-the-seam.md) | `nothing-crosses-unasserted` |
| [`a-time-names-its-zone`](a-time-names-its-zone.md) | `nothing-crosses-unasserted` |
| [`no-nullable-columns`](no-nullable-columns.md) | `absence-is-absence` |
| [`no-database-defaults`](no-database-defaults.md) | `absence-is-absence` |
| [`persistence-holds-no-behaviour`](persistence-holds-no-behaviour.md) | `model-concerns-not-groups` |
| [`a-shape-is-composed-not-flattened`](a-shape-is-composed-not-flattened.md) | `model-concerns-not-groups` |
| [`no-lifecycle-callbacks`](no-lifecycle-callbacks.md) | `tell-dont-ask` |
| [`no-decisions-in-request-handling`](no-decisions-in-request-handling.md) | `tell-dont-ask` |
| [`no-type-interrogation`](no-type-interrogation.md) | `one-way-to-say-each-thing` |
| [`code-is-written-not-generated`](code-is-written-not-generated.md) | `nothing-is-hidden` |
| [`no-silent-coercion`](no-silent-coercion.md) | `nothing-fails-quietly` |
| [`a-guard-states-its-limit`](a-guard-states-its-limit.md) | `nothing-fails-quietly` |
| [`enforcement-messages-are-documentation`](enforcement-messages-are-documentation.md) | `nothing-is-hidden` |

Seventeen. `make-the-wrong-thing-impossible` produces no law of its own — it produces every
guard on this list, and the rule that each is tested by removal.
