# CLAUDE.md

Root field manual. Delivered to every session in this repo by design, so it is exempt from the
6 KB budget every other `CLAUDE.md` here carries — that exemption is not licence to let it grow
for any other reason.

## What this gem is

A RuboCop plugin: cops for operation shape (one class per operation, a declared call-graph
matrix, typed construction, no industry terms in code) plus a CLI (`exe/shipshape`) that
ratchets, reports and installs base classes into an application that adopts the canon. It does
not enforce its own canon on itself — see "This repo is not governed by its own cops," below.

## Where the actual rules live

- [`docs/principles.md`](docs/principles.md) — supreme document, why the shape is the shape.
- [`docs/laws/`](docs/laws/README.md) — what must be true and what guards it. One law, one
  file: statement, principle, guard, guard's limit.
- [`docs/decomposing/`](docs/decomposing/README.md) — one ordered procedure per legacy pattern.
- [`docs/rails-patterns.md`](docs/rails-patterns.md), [`docs/rails-failure-patterns.md`](docs/rails-failure-patterns.md) —
  reference verdicts on named patterns and known failures.

Each of those four has a `.agent.md` twin beside it — a compacted copy that defers to the human
original on conflict. The twins are not this mechanism: nothing loads them unprompted any more
than it loads the document they compact. This `CLAUDE.md` chain is what actually reaches an
agent; treat the twins as another source to read, not as the delivery.

**Never cite a law, a procedure or this file by number** — not a section, not a step. Name the
rule; a number is an address the reader has to go fetch the meaning from.

## `shipshape rules` writes a file named `CLAUDE.md` — never run it here

`bundle exec shipshape rules` generates the layout briefing a *consuming application* installs
at its own root, derived from that application's `.rubocop.yml` and its `Kinds`. Its default
output filename is `CLAUDE.md`. Run inside this gem's own checkout it would overwrite this
hand-compacted file with a description of an `app/deeds`-shaped layout this repo does not have.
This repo is the tool that writes that file for someone else; it is never that file's target.

## This repo is not governed by its own cops

`Shipshape/CallGraph`'s `Kinds` name `app/deeds`, `app/questions`, and so on — this gem has
none of those. `.rubocop-dogfood.yml` (deliberately **not** named `.rubocop.yml` — see its own
header comment) enables exactly one cop against `lib/**` and `test/**`:
`Shipshape/CommentBudget`. Every other law in `docs/laws/` binds code this gem ships to
*other* repositories, not this one. Do not "fix" this repo's own `lib/` or `test/` files to
satisfy a law whose guard is not even wired here.

## Running the suite

```sh
bundle exec rake              # test + lint (default task)
bundle exec rake test:removal # spawns a process per cop; neuters it; confirms its test reddens
bundle exec rake lint         # rubocop --config .rubocop-dogfood.yml
```

**There is no root `.rubocop.yml`**, on purpose. Never run bare `bundle exec rubocop` from this
repo expecting it to pick up this gem's own linting — with no `.rubocop.yml` here, RuboCop's
upward config search walks past this checkout entirely. Always pass the pinned config, exactly
as `rake lint` does. The same upward-search failure mode bites the CLI's own target-repo config
resolution; see `lib/shipshape/CLAUDE.md`.

## Ruby floor: 2.7.0

`shipshape.gemspec` pins `required_ruby_version >= 2.7.0` because this gem runs inside both a
2.7 application and whatever RuboCop itself requires. **No pattern matching, no `Data.define`,
no endless methods**, anywhere under `lib/` — all newer than 2.7 syntax.

## The suite's own meta-guards

Four tests hold the canon internally consistent and are worth knowing exist before touching a
law, a cop, or a procedure:

- `test/canon_test.rb` — a law names a cop that exists (or says "not built yet"); every cop is
  named by a law; every cop has a test; every cop's test proves itself by removal; every cop is
  named by a decomposing procedure (or is declared exempt, with a reason); the laws and
  decomposing indexes list every file.
- `test/documents_have_one_shape_test.rb` — every procedure carries the same sections; no
  document cites a section by number; every prose document keeps a shorter `.agent.md` twin.
- `test/removal_test.rb` and `test/canaries_test.rb` — see `lib/rubocop/cop/shipshape/CLAUDE.md`.

Neither `canon_test.rb` nor `documents_have_one_shape_test.rb` currently knows this
`CLAUDE.md` chain exists — they govern `docs/laws/`, `docs/decomposing/`, and the four
`.agent.md` twins, not this mechanism. Adding `CLAUDE.md` files did not require teaching either
test anything new; it did not weaken either guard.
