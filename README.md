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
    workflow:         ['app/workflows/**/*.rb']
    command:          ['app/commands/**/*.rb']
    query:            ['app/queries/**/*.rb']
    gateway:          ['app/gateways/**/*.rb']
    entity:           ['app/entities/**/*.rb']
    record:           ['app/records/**/*.rb']
  Matrix:
    request_handling: [workflow, command, query]
    workflow:         [command, query, gateway]
    command:          [query, gateway, entity, record]
    query:            [entity, record]
    gateway:          [entity]
    entity:           [entity]
    record:           []
```

A class's kind comes from where it is filed. A call whose (caller kind, callee kind) pair
is absent from the matrix is an offence. A constant that resolves to no file under a
declared kind is skipped, not failed.

The four rows that carry the argument:

- **A query may not call a query.** A query is one read. A query calling a query is two
  reads wearing one name, the second invisible to whoever asked — the shape an N+1 arrives
  in.
- **A command may not call a command.** A command is one write. Sequencing writes is the
  workflow's job, and a command calling a command has become a workflow without saying so
  — with none of a workflow's obligations, which is the real cost.
- **A workflow may not call a workflow.** Its whole content is its sequence, and nesting
  hides the sequence.
- **A gateway is a command that crosses the process boundary**, and the only kind allowed
  to talk to anything outside. It reaches no record and no query, so the external call and
  the write recording its result stay two visible steps — which is what makes the pair
  retryable.

## Tests

```sh
bin/ci
```

Every cop ships a test proven to fail: delete the guard, watch it go red, restore it.

## Licence

MIT.
