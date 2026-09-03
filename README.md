# shipshape

**MVC, taken apart.**

The M is not one thing. It is workflows, commands, queries, shapes and records, and a codebase
that calls all five "model" cannot tell you where a rule lives. shipshape gives each a place,
keeps it with cops that can only ratchet, and ships the canon to agents as well as to CI.

**No industry terms in code.** A word the business owns — a rate, a levy, a tier, a status — is
a row, not a branch. Held as code it cannot change without a deploy, differ per tenant, or be
corrected by the person who knows the answer. Every procedure in
[`docs/decomposing/`](docs/decomposing/README.md) starts there.

**Not a package-boundary tool.** Packwerk enforces package boundaries; shipshape enforces
operation shape — one operation per class, typed at the door, parsing at the seam, invariants in
the schema, and a declared matrix of which kinds may call which. The two compose.

## Where the thinking is

| If you want | Read |
|---|---|
| Why the code takes this shape | [`docs/principles.md`](docs/principles.md) |
| What must be true, and what checks it | [`docs/laws/`](docs/laws/README.md) |
| How to take a legacy shape apart | [`docs/decomposing/`](docs/decomposing/README.md) |
| How to adopt it on a repo that already runs | [an adoption order](docs/decomposing/an-adoption-order.md) |
| Which Rails failures this covers, and which it does not | [`docs/rails-failure-patterns.md`](docs/rails-failure-patterns.md) |
| What it does about the patterns teams reach for | [`docs/rails-patterns.md`](docs/rails-patterns.md) |

Every law states its guard **and what that guard misses**, because a blind spot nobody wrote
down is read as coverage.

**What it does not do:** nothing here proves behaviour is preserved. `shipshape check` proves
the offence count fell; whether the code still works is the suite's job, which is why
`shipshape next` offers files a test names before the rest.

## Installing the base classes

```sh
bundle exec shipshape install          # no authorisation
bundle exec shipshape install --auth   # every door checks a permission
```

Writes the base classes into `app/shipshape/` and includes `TypedParams` into your
`ApplicationController`. **They are generated, not inherited from this gem** — a base class you
can open in your own repository beats one buried in a dependency. Nothing is ever overwritten:
a file already on disk that still matches what this run would write is left alone and reported
as kept; one that does not gets the new version written beside it as `<file>.new`, reported as
`DIFFERS`, and left for you to diff against your own copy. `install` cannot know why a file
differs — it never recorded what wrote it — so it only ever compares against what *this* run
would write, and it prints the flags this run used: a common cause is installing with `--auth`
one time and without it the next, not the template moving on. `install` never diffs the two for
you, because that diff would mix your edits into the gem's changes with no way to tell which is
which. A `.new` is never deleted either, even after it stops differing — once the file beside it
matches this run again, `install` reports it `STALE` and leaves removing it to you. Neither kind
of leftover is gitignored: a `.new` marks something still to review, and a `git status` that
hides it is the wrong default. They sit outside the governed trees because a base class is not an
instance of the thing it defines: `Command` is not a command.

**Authorisation is opt-in and off by default.** Base classes demanding an `actor:` on day one
would stop every call site at once — an outage, not a migration. See
[`a-permission-is-the-class-name`](docs/laws/a-permission-is-the-class-name.md).

| Written | What it is |
|---|---|
| `Workflow` | sequences operations across several transactions; answers with a `Result` |
| `Command` | one transaction, however many writes it holds; answers with a `Result` |
| `Query` | never writes; answers with a shape or an array of them, no envelope |
| `IoCommand` / `IoQuery` | changing and reading state outside this process |
| `LegacyCommand` / `LegacyQuery` | the two doors to the old world |
| `Shape` | a domain object, detached from the database, with value semantics |
| `Result` | `success(value)` / `failure(:code, value)` — an expected failure, never a bug |
| `TypedArguments` | asserts every keyword where it arrives |
| `TypedParams` | parses request input at the seam, once |
| `Boolean` | a name for true-or-false that reopens nothing |

## Trying it

```ruby
gem "shipshape", require: false   # Gemfile
```

```yaml
require:                          # .rubocop.yml
  - shipshape
```

The defaults assume `app/commands`, `app/queries`, `app/workflows`, `app/shapes`, `app/records`,
`app/legacy` and their `packs/*/` equivalents. Override `Kinds` to match what your application
already calls things.

**A class's kind comes from what it inherits.** The path only decides whether a file is governed
at all, which is why two kinds can share one glob.

| Kind | May call |
|---|---|
| request_handling / entry_point | every operation kind, view_component, shape |
| workflow | command, query, io_command, io_query, legacy_command, legacy_query, shape |
| command | query, legacy_query, shape, record |
| query | shape, record |
| io_command | io_query, shape |
| io_query | shape |
| legacy_command | query, legacy_query, shape, record |
| legacy_query | shape, record |
| view_component | shape |
| shape / record | nothing |

**No kind calls a sister, and every kind is its own sister** — a rule in the cop, not the matrix,
so a row naming one stops the run. A sister call is how a class quietly becomes the kind above
it: a command sequencing commands is a workflow that never said so, and a query composing
queries is the read that becomes an N+1.
[`the-call-graph-is-declared`](docs/laws/the-call-graph-is-declared.md) carries the rest.

On a real application most existing controllers violate the matrix on day one. That is correct
and survivable: the baseline comes from the merge-base, only new violations fail, and the count
is the migration progress.

## The rules file an agent is handed

```sh
bundle exec shipshape rules            # writes CLAUDE.md
bundle exec shipshape rules --out AGENTS.md
```

Derived from your `.rubocop.yml` and the loaded cops. **Regenerate rather than edit** — a
hand-kept description of the layout is a second copy of it, and the copy goes stale.

## Decomposing

[`docs/decomposing/`](docs/decomposing/README.md) holds one ordered procedure per legacy
pattern, each with something to run at every step. Start with
[an adoption order](docs/decomposing/an-adoption-order.md).

**They share one step, and it comes before the split: no industry terms in code.** Each pattern
is that defect in a different costume — single-table inheritance is a type column written as
classes, a state machine is a transition table written as branches, callbacks are an ordering
written as registration order. Code that encodes facts grows every time the facts grow, and
refactoring never fixes that, because the code was never the problem.

The test is who you ask when it is wrong: a person means data, a programmer means control flow.
"Is it a constant?" is the failing question — constants are code.

Two that surprise people. **Thread the ambient reads out before splitting**: `Time.current` in
two methods makes them look independent until they are not. And **move the data pretending to be
code first** — a `case` over domain literals answering with literals is a lookup table someone
wrote as code, and it is usually *why* the service grew. Split it into fifteen classes and the
branch is still there, still needing a deploy to add a row.

## Handing the work to an agent

```sh
bundle exec shipshape next            # the next few files, with the rules they break
bundle exec shipshape next --json
```

An agent handed a whole codebase does the wrong thing. It needs one file, the rules that file
breaks, and a way to know it finished. Each unit carries the **full offence messages** — rule,
reason, example — so it is actionable with nothing else loaded.

**Best-covered first, counted per method**, because a file-level answer was nearly useless:
`story.rb` has a test, and that says nothing about the method you are about to move.

```text
── 2. app/models/story.rb
   24 of 80 methods named in tests
   NOT NAMED BY ANY TEST: accepting_comments?, archiveorg_url, as_json, …
```

This is a name match, not a call graph: it answers "would anything notice". **Extracting a rule
out of a method nothing exercises is how a refactor becomes an outage**, and no cop here would
notice — the honest limit of the whole tool, made visible per method instead of per file.

## Fixing the mechanical part

```sh
bundle exec rubocop -A --only Shipshape/NoSilentCoercion,Shipshape/NoUnparsedLookup,Shipshape/NoInlineParamParse
```

`params[:page].to_i` becomes `integer_param!(:page)`. Deterministic rewrites, about 7% of what
shipshape finds on a real codebase.

**`SafeAutoCorrect: false`, so they arrive under `-A` and never `-a`.** The correction is not
behaviour-preserving on purpose — a silent `0` becomes a bounce, which is the rule.

**What is deliberately not corrected**, because the parser cannot be derived from a name:
`where(short_id: params[:story_id])` is reported and left alone. Rewriting it broke lobsters in
testing — its `short_id` is base 36. Only `find(params[:id])` is corrected positionally, because
Rails makes the primary key an integer.

## Knowing how much of your code the guards can reach

```sh
bundle exec shipshape coverage
```

A file resolving to no kind is skipped by every kind-scoped cop — silently, and
indistinguishably from a file they approved of. **A clean run means nothing until you know what
fraction of the tree was inspected.**

Over six public Rails codebases with the default layout the governed fraction was 12%, 20%, 26%,
29%, 37% and 44% — and **0% for an engine monorepo**, where every path is `core/app/models/…`.
That one reported nineteen offences across 1203 files it never opened, and looked healthy. The
fix is always to declare the trees your repository actually uses.

## Proving the guards are running

```sh
bundle exec shipshape canaries --plant   # writes test/canaries/, one violation per cop
bundle exec shipshape canaries           # every cop must catch its own
```

A guard that does not run reports the same thing as a guard that finds nothing: zero. That has
happened here — cops run over a 647-file tree reported clean, and the truth was that no glob
matched. `canaries` proves a cop *can* fire; `coverage` proves the cops can *reach your code*.
Both questions have to be asked.

## Running against an application that pins an older RuboCop

Every cop subclasses `RuboCop::Cop::Base`, which arrived in RuboCop 1.0, so that is the floor.
An application pinned lower does not have to upgrade — run shipshape from its own bundle:

```sh
# tools/shipshape/Gemfile: gem "shipshape"; gem "rubocop", ">= 1.0"
BUNDLE_GEMFILE=tools/shipshape/Gemfile bundle exec shipshape check
```

If the application's own `.rubocop.yml` cannot load beside RuboCop 1.x — it `require:`s a plugin
pinned to 0.x — pass `--config` a file **at the repository root**. A config in a subdirectory
resolves its globs against that directory and silences every kind-scoped cop.

## The ratchet

```sh
bundle exec shipshape check [--trunk <ref>] [--config <path>]
```

Counts each cop's offences here and at the commit this branch diverged from, and fails only
where a count **rose**. An inherited pile is not your bill; one new violation is.

**There is no checked-in baseline file.** A snapshot of existing violations has a regenerate
button, and pressing it on a red build erases the signal the guard exists to raise. The baseline
is derived from git every run, through a detached worktree in a temporary directory.

**Both trees are measured with the head tree's configuration**, so enabling a cop is free and
holds the line from that moment. Only `Shipshape/*` cops are counted.

**Stated limits.** It compares counts, not identities, so fixing one offence and adding another
in the same cop nets to green. A moved file counts as new offences in head and removed ones in
base. Only the root config is copied to the base tree. The merge-base is used rather than the
trunk's tip, so an offence somebody else pushed after you branched is not billed to you. `OFF`
is read from the root config alone — a cop a subdirectory `.rubocop.yml` disables is invisible
to it, so it reports nothing off while `rubocop` itself, resolving per file, silences that cop
there.

## Tests

```sh
bundle exec rake              # the suite
bundle exec rake test:removal # neuter each cop in turn, confirm its own test goes red
```

## Licence

MIT.
