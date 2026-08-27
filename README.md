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
| What is being built, and in what order | [`docs/specs/`](docs/specs/) |

Nine principles, sixteen laws. Every law states its guard **and what that guard misses**,
because a blind spot nobody wrote down is read as coverage.

## Status

**Early. Two cops of sixteen are built.**

- `Shipshape/CallGraph` — holds
  [`the-call-graph-is-declared`](docs/laws/the-call-graph-is-declared.md)
- `Shipshape/OneOperationOneClass` — holds
  [`one-operation-one-class`](docs/laws/one-operation-one-class.md)

The layout — which paths hold which kind — is declared **once**, on `Shipshape/CallGraph`,
and every other cop reads it from there. Repeating it per cop would be a second copy of one
fact, and the copy is the one that goes stale.

The rest are specified in `docs/laws/` and not yet written. The ratchet and the
agent-rules generator are not built either. Until a law's guard exists, that law is a
convention held by review, and the law file says so.

## Installing the base classes

```sh
bundle exec shipshape install
```

Writes the base classes into `app/shipshape/` and includes `TypedParams` into your
`ApplicationController`. **They are generated, not inherited from this gem** — a base class
you can open in your own repository beats one buried in a dependency, and shipshape stays a
development dependency.

Nothing is ever overwritten, and the wiring is idempotent. If there is no
`ApplicationController` it says so and exits non-zero rather than reporting success: a
concern nobody includes parses nothing, while the application looks equipped.

They land outside the governed trees because a base class is not an instance of the thing
it defines — `Command` is not a command.

| Written | What it is |
|---|---|
| `Workflow` | sequences commands and queries across several transactions; answers with a `Result` |
| `Command` | one write, in exactly one transaction; answers with a `Result` |
| `Query` | one read; answers with an entity or an array of them, no envelope |
| `LegacyCommand` / `LegacyQuery` | the two doors to the old world, sisters of the pair above |
| `Entity` | a domain object, detached from the database, with value semantics |
| `Result` | `success(value)` / `failure(:code)` — an expected failure, never a bug |
| `TypedArguments` | asserts every keyword where it arrives |
| `TypedParams` | parses request input at the seam, once |
| `Boolean` | a name for true-or-false that reopens nothing |

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
    entity:           []
    record:           []
```

A class's kind comes from where it is filed. A kind is a list of globs, so a Packwerk
layout needs no second mechanism — add `packs/*/commands/**/*.rb` beside
`app/commands/**/*.rb` and each pack becomes its own autoload root.

**Two kinds carry a filename suffix, for one reason: they are the two that are
infrastructure rather than domain.** Everything the MVC model used to hold is now split
across workflows, commands, queries and entities — so what is still called a record is
only the table, and `*_record.rb` says so out loud.

 A call whose (caller kind, callee kind) pair
is absent from the matrix is an offence. A constant that resolves to no file under a
declared kind is skipped, not failed.

**No kind calls its own kind.** That rule lives in the cop, not the matrix — a row naming
itself is refused as a contradiction rather than honoured as a permission. A sister call is
how a class quietly becomes the kind above it, and everything below is a consequence of
that one rule:

- **A command is one write.** A command calling a command is sequencing writes, which is a
  workflow's job — so it has become a workflow without saying so, and without a workflow's
  obligations.
- **A query is one read.** A query calling a query is two reads wearing one name, the
  second invisible to whoever asked. The shape an N+1 arrives in.
- **A workflow's whole content is its sequence**, and nesting hides it.
- **An entity holds another entity; it does not build one.**

**A gateway is a command that crosses the process boundary**, and the only kind allowed to
talk to anything outside. It reaches no record and no query, so the external call and the
write recording its result stay two visible steps — which is what makes the pair retryable.
Request handling cannot reach one directly: an external call has a domain meaning, and that
meaning lives in the command or workflow that wanted it.

## Tests

```sh
bin/ci
```

Every cop ships a test proven to fail: delete the guard, watch it go red, restore it.

## Licence

MIT.
