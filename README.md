# shipshape

A canon for Rails codebases, and the guards that hold it.

It detangles by giving every kind of code a place, then keeps the place with cops that can
only ratchet — the count of violations falls and never rises. It ships the canon to agents
as well as to CI, so the rules reach the thing doing the editing.

**Not a package-boundary tool.** Packwerk enforces package boundaries; shipshape enforces
operation shape — one operation per class, typed at the door, parsing at the seam,
invariants in the schema, and a declared matrix of which kinds of class may call which.
The two compose.

## Where the thinking is

| If you want | Read |
|---|---|
| Why the code takes this shape | [`docs/principles.md`](docs/principles.md) |
| What must be true, and what checks it | [`docs/laws/`](docs/laws/README.md) |
| What is being built, and in what order | [`docs/superpowers/specs/`](docs/superpowers/specs/) |

Nine principles, sixteen laws. Every law states its guard **and what that guard misses**,
because a blind spot nobody wrote down is read as coverage.

## Status

**Early. One cop of sixteen is built.**

- `Shipshape/CallGraph` — holds
  [`the-call-graph-is-declared`](docs/laws/the-call-graph-is-declared.md)

The rest are specified in `docs/laws/` and not yet written. The ratchet and the
agent-rules generator are not built either. Until a law's guard exists, that law is a
convention held by review, and the law file says so.

## Trying it

```ruby
# Gemfile
gem "shipshape", require: false
```

```yaml
# .rubocop.yml
require:
  - shipshape

Shipshape/CallGraph:
  Kinds:
    request_handling: ['app/controllers/**/*.rb']
    operation:        ['app/operations/**/*.rb']
    value:            ['app/values/**/*.rb']
    record:           ['app/records/**/*.rb']
  Matrix:
    request_handling: [operation]
    operation:        [operation, value, record]
    value:            [value]
    record:           []
```

A class's kind comes from where it is filed. A call whose (caller kind, callee kind) pair
is absent from the matrix is an offence. A constant that resolves to no file under a
declared kind is skipped, not failed.

## Tests

```sh
bin/ci
```

Every cop ships a test proven to fail: delete the guard, watch it go red, restore it.

## Licence

MIT.
