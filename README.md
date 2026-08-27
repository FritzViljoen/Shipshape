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
```

The defaults assume `app/commands`, `app/queries`, `app/workflows`, `app/entities`,
`app/records`, `app/legacy` and their `packs/*/` equivalents. Override `Kinds` to match
whatever your application already calls things.

**A class's kind comes from what it inherits.** The path only decides whether a file is
governed at all, which is why two kinds can share one glob — the legacy pair do, and
`< LegacyQuery` versus `< LegacyCommand` tells them apart.

| Kind | May call |
|---|---|
| request_handling | workflow, command, query, legacy_command, legacy_query |
| workflow | command, query, legacy_command, legacy_query, entity |
| command | query, legacy_query, entity, record |
| query | entity, record |
| legacy_command | query, legacy_query, entity, record |
| legacy_query | entity, record |
| entity | nothing |
| record | nothing |

**No kind calls a sister, and every kind is its own sister.** That rule lives in the cop,
not the matrix — a row naming a sister stops the run rather than being honoured. A sister
call is how a class quietly becomes the kind above it, and the rest follows from it:

- **A command is exactly one transaction. A workflow is several.** A command calling a
  command has either nested a transaction or silently widened one, and nobody decided
  which. A workflow crossing transactions is *obliged* to make each step idempotent and
  each intermediate state legal — sequencing writes is its job because it is the thing that
  accepted that bill. A `legacy_command` is a command that wraps something old, so it is a
  sister too.
- **A query is one read.** A query calling a query is two reads wearing one name, the
  second invisible to whoever asked. The shape an N+1 arrives in.
- **A workflow's whole content is its sequence**, and nesting hides it.
- **An entity holds another entity; it does not build one.**
- **A class naming itself is not a sister call** — `Result.success(...)` inside `Result` is
  one entity, not two talking.

**There is no kind for talking to the outside.** A read of somebody else's store is a query;
a write to it is a command. REST drew that line already, and a kind whose only claim is that
the store belongs to someone else forbids nothing the existing pair does not.

**Two kinds carry a filename suffix** — `*_controller.rb` and `*_record.rb` — because they
are the two that are infrastructure rather than domain. Everything the MVC model used to
hold is now split across workflows, commands, queries and entities, so what is still called
a record is only the table, and the name says so.

**The two `*_legacy.rb` doors are the only classes permitted to speak to the old world.**
The new shape admits only its own kinds — a workflow sequences commands and queries and
nothing else — so an unwrapped legacy service cannot be called from one at all. Wrapping is
how old code gets in, and the mark keeps the crossing visible at the call site.

Their population is the migration backlog. It **rises** while the old world is being pulled
into the new shape and falls only as each wrapped thing is rewritten — a curve, not a
ratchet. The ratchet governs violations, and a door is not a violation.

A constant that resolves to no file under a declared kind is skipped, not failed.

## Tests

```sh
bin/ci
```

Every cop ships a test proven to fail: delete the guard, watch it go red, restore it.

## Licence

MIT.
