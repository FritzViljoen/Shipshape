# Principles — agent copy

[`principles.md`](principles.md) is the document. This governs nothing. On conflict, the human
copy wins.

Nothing checks a principle. Nothing can. A principle produces a **law**; the law has the guard.
Guards are named in [`laws/`](laws/), never here.

You need this file to answer one question: which law came from where. That is the table.

| principle | one line | produces |
|---|---|---|
| `good-boundaries-make-good-neighbours` | one home per rule. Which homes reach which is declared | `a-question-never-writes`, `io-is-its-own-kind`, `deferral-is-one-deed`, `the-call-graph-is-declared`, `nothing-travels-off-the-call-path` |
| `nothing-crosses-unasserted` | what crosses a boundary is stated there and checked there | `arguments-are-typed-at-construction`, `input-is-parsed-at-the-seam`, `a-time-names-its-zone` |
| `absence-is-absence` | a gap is not a value. A NULL means "off", "inherit", and "not said" at once, so "nobody said" is the absence of a row, never a nullable column | `absence-is-absence-never-a-value`, `no-database-defaults` |
| `model-concerns-not-groups` | a shared noun is not a shared concern | `persistence-holds-no-behaviour`, `a-shape-is-composed-not-flattened` |
| `no-industry-terms-in-code` | a word the business owns is a row, not a branch | the "Rules that are really data" measure |
| `tell-dont-ask` | send the message. Do not pull the state out and decide for it | `a-deed-runs-twice`, `no-lifecycle-callbacks`, `no-decisions-in-request-handling` |
| `one-way-to-say-each-thing` | one operation, one class, one way to call it | `one-operation-one-class`, `no-test-factories`, `a-comment-is-a-second-copy`, `no-type-interrogation`, `one-mechanism-guards-everything`, `a-permission-is-the-class-name` |
| `nothing-is-hidden` | every rule is written where a reader greps for it | `personal-data-is-declared-and-erasable`, `a-schedule-is-a-row`, `an-operation-is-a-leaf`, `code-is-written-not-generated`, `enforcement-messages-are-documentation`, `a-test-inherits-what-it-needs`, `co-change-is-a-fact-not-a-verdict`, `a-method-carries-its-own-weight` |
| `make-the-wrong-thing-impossible` | encode the rule. Do not write it down and hope | `a-deed-is-one-transaction`, `a-kind-is-inherited-not-only-placed`, and every law's guard |
| `nothing-fails-quietly` | an operation completes, or says why it did not | `an-operation-answers-a-result`, `every-operation-reports-what-it-did`, `no-silent-coercion`, `a-guard-states-its-limit` |

## Rules for you

Do not cite a principle as a reason to fail a build. Cite the law.

A principle producing no law is a defect. Say so; do not invent the law.

## Not here

Why any of these is believed. The evidence, including two that rest on contested ground —
`nothing-is-hidden`, where a respected source disagrees, and `one-way-to-say-each-thing`, which
rests on a prediction and states what would falsify it. Arguing that a law is wrong starts in
[`principles.md`](principles.md).
