# Laws

*What must be true. Below the [principles](../principles.md), which decide why.*

A law is what a principle produces where it produces something checkable. Each file states
four things and stops:

- **what must be true**
- **the principle it serves** — and, where two produce it, which one governs on conflict
- **the guard** that holds it
- **the guard's limit** — what a passing run does not prove

> **Every law here names a guard, and `CanonTest` fails the build if it does not** — a cop
> that exists, one of the guards that ship with this gem's own suite, or the words *not
> built yet*, which make it a convention. That is a narrower claim than it looks: it holds
> that a guard is *named*, never that it covers everything the law describes. Each law's
> **guard's limit** is where that gap is written down, and it is the part worth reading.

A law with no guard says so, permanently, and is called a convention. Calling it a law does
not make it hold.

## The list

| Law | Principle |
|---|---|
| [`one-operation-one-class`](one-operation-one-class.md) | `one-way-to-say-each-thing` |
| [`an-operation-answers-a-result`](an-operation-answers-a-result.md) | `nothing-fails-quietly` |
| [`a-deed-is-one-transaction`](a-deed-is-one-transaction.md) | `make-the-wrong-thing-impossible` |
| [`a-question-never-writes`](a-question-never-writes.md) | `good-boundaries-make-good-neighbours` |
| [`io-is-its-own-kind`](io-is-its-own-kind.md) | `good-boundaries-make-good-neighbours` |
| [`personal-data-is-declared-and-erasable`](personal-data-is-declared-and-erasable.md) | `nothing-is-hidden` |
| [`a-deed-runs-twice`](a-deed-runs-twice.md) | `tell-dont-ask` |
| [`every-operation-reports-what-it-did`](every-operation-reports-what-it-did.md) | `nothing-fails-quietly` |
| [`deferral-is-one-deed`](deferral-is-one-deed.md) | `good-boundaries-make-good-neighbours` |
| [`a-schedule-is-a-row`](a-schedule-is-a-row.md) | `nothing-is-hidden` |
| [`no-test-factories`](no-test-factories.md) | `one-way-to-say-each-thing` |
| [`an-operation-is-a-leaf`](an-operation-is-a-leaf.md) | `nothing-is-hidden` |
| [`the-call-graph-is-declared`](the-call-graph-is-declared.md) | `good-boundaries-make-good-neighbours` |
| [`a-kind-is-inherited-not-only-placed`](a-kind-is-inherited-not-only-placed.md) | `make-the-wrong-thing-impossible` |
| [`nothing-travels-off-the-call-path`](nothing-travels-off-the-call-path.md) | `good-boundaries-make-good-neighbours` |
| [`arguments-are-typed-at-construction`](arguments-are-typed-at-construction.md) | `nothing-crosses-unasserted` |
| [`input-is-parsed-at-the-seam`](input-is-parsed-at-the-seam.md) | `nothing-crosses-unasserted` |
| [`a-time-names-its-zone`](a-time-names-its-zone.md) | `nothing-crosses-unasserted` |
| [`absence-is-absence-never-a-value`](absence-is-absence-never-a-value.md) | `absence-is-absence` |
| [`no-database-defaults`](no-database-defaults.md) | `absence-is-absence` |
| [`persistence-holds-no-behaviour`](persistence-holds-no-behaviour.md) | `model-concerns-not-groups` |
| [`a-shape-is-composed-not-flattened`](a-shape-is-composed-not-flattened.md) | `model-concerns-not-groups` |
| [`a-comment-is-a-second-copy`](a-comment-is-a-second-copy.md) | `one-way-to-say-each-thing` |
| [`no-lifecycle-callbacks`](no-lifecycle-callbacks.md) | `tell-dont-ask` |
| [`no-decisions-in-request-handling`](no-decisions-in-request-handling.md) | `tell-dont-ask` |
| [`no-type-interrogation`](no-type-interrogation.md) | `one-way-to-say-each-thing` |
| [`code-is-written-not-generated`](code-is-written-not-generated.md) | `nothing-is-hidden` |
| [`no-silent-coercion`](no-silent-coercion.md) | `nothing-fails-quietly` |
| [`a-guard-states-its-limit`](a-guard-states-its-limit.md) | `nothing-fails-quietly` |
| [`enforcement-messages-are-documentation`](enforcement-messages-are-documentation.md) | `nothing-is-hidden` |
| [`one-mechanism-guards-everything`](one-mechanism-guards-everything.md) | `one-way-to-say-each-thing` |
| [`a-permission-is-the-class-name`](a-permission-is-the-class-name.md) | `one-way-to-say-each-thing` |
| [`a-test-inherits-what-it-needs`](a-test-inherits-what-it-needs.md) | `nothing-is-hidden` |
| [`co-change-is-a-fact-not-a-verdict`](co-change-is-a-fact-not-a-verdict.md) | `nothing-is-hidden` |
| [`a-method-carries-its-own-weight`](a-method-carries-its-own-weight.md) | `nothing-is-hidden` |

`make-the-wrong-thing-impossible` also produces every guard on this list, and the rule that
each is tested by removal — beyond the two laws above it names as its own.
