# shipshape — agent copy

[`README.md`](README.md) is the document. This governs nothing. On conflict, the human copy wins.

Every class is one kind. Superclass decides the kind. Path decides whether the file is governed.
A matrix declares which kind may call which. Cops hold it. Counts may fall, never rise.

## Run these first, in this order

```sh
bundle exec shipshape coverage   # how much of the tree resolves to a kind
bundle exec shipshape canaries   # every cop caught a planted violation
bundle exec shipshape edges      # edges nothing in the suite names
```

Coverage below ~90% means most of the repo was never opened. A clean report over an undeclared
layout is meaningless. Check coverage before believing any number.

## Then

```sh
bundle exec shipshape report                 # the diagnostic. read-only, needs no config
bundle exec shipshape next                   # one file, its offences, whether a test names it
bundle exec shipshape install [--auth]       # base classes into app/shipshape/
bundle exec shipshape rules --out AGENTS.md  # the layout, derived. regenerate, never edit
bundle exec shipshape check                  # the ratchet, against the merge base
```

## Where to read

| you want | read |
|---|---|
| what must be true, what checks it | [`docs/laws/`](docs/laws/README.md) |
| how to take one shape apart | [`docs/decomposing/`](docs/decomposing/README.md) |
| adopting on a live repo | [an adoption order](docs/decomposing/an-adoption-order.md) |
| why the shape is this shape | [`docs/principles.md`](docs/principles.md) |
| which failures are covered | [`docs/rails-failure-patterns.md`](docs/rails-failure-patterns.md) |
| a pattern you already know | [`docs/rails-patterns.md`](docs/rails-patterns.md) |

## Rules for you

Read the offence message. It states the rule, the reason, and a correct example. Do not guess
from the cop name.

Read a law's `Guard's limit` before quoting its `Guard`.

Nothing here proves behaviour is preserved. `check` proves a count fell. The suite proves the
code works. Characterise the edges before moving anything.

Do not add exemptions. Do not regenerate a baseline. There isn't one.

## Not here

Older-RuboCop setup. Licence. How the baseline is derived. See [`README.md`](README.md).
