# shipshape — design

## What it is

A canon for Rails codebases, and the guards that hold it.

It detangles by giving every kind of code a place, then keeps the place with cops
that can only ratchet — the count of violations falls and never rises. It ships the
canon to agents as well as to CI, so the rules reach the thing doing the editing.

## Why

Generating code stopped being the expensive half. Reading it did not, and nobody
pays for volume except the reader. A file grows to a thousand lines because nothing
in it had a home, and by then there are no seams to refactor along.

So the brake has to be structural. A guard is not there to make the code good — it
is there to make the code's shape knowable without reading it. That is what caps
comprehension cost: not shorter code, predictable code.

## Non-goals

- **It does not move code.** Cops find; people move. Auto-migration is not v1 and
  may never be honest.
- **No base classes in v1.** No `Service`, `Command`, `Query`, `TypedArguments`.
  They are the most opinionated part and the part every team renames. They wait
  until real consumers say what shape they need.
- **It is not a package-boundary tool.** Packwerk enforces package boundaries.
  shipshape enforces operation shape — one operation per class, typed at the door,
  parsing at the seam, invariants in the schema. Complementary, and the README says
  so on the first screen.

## The canon

Three layers, and the build order is the same as the layering.

**Principle → law → guard.**

- A **principle** is a judgement. Nothing checks it and nothing can.
- A **law** is what a principle produces where it produces something checkable.
- A **guard** is the cop that holds a law. A law with no guard says so, and is
  called a convention rather than a law.

**Written fresh.** Two existing repos already implement these ideas and disagree with
each other — one splits `Command`/`Query` and returns a `Result`, the other has a single
`Service` that answers with what it made and explicitly superseded the `Result`. The
canon is not a transcription of either. Distillation is the point of the exercise, and
transcription would preserve the divergence instead of resolving it.

**Size is the test.** Between them the two repos hold 48 cops and roughly 25 written
laws. The target here is **6–8 principles and 10–15 laws**. A canon that comes out at
40 laws has failed: what could not earn a line at that size was app-specific, not a
principle.

**A law file states four things and stops:** what must be true, the principle it
serves, the guard that holds it, and what that guard misses.

## Layout

```
docs/principles.md        the judgements. unchecked, and nothing can check them
docs/laws/<name>.md       one file per law
lib/shipshape/cop/…       the guards
lib/shipshape/baseline.rb the git-derived ratchet
lib/shipshape/rules.rb    emits CLAUDE.md / AGENTS.md from docs/laws
exe/shipshape             the CLI
test/
```

## Cops

One RuboCop department, flat names — `Shipshape/NoNullableColumns`. Matches how
`rubocop-rspec` namespaces, and avoids colliding with a host app's own cops.

Cops ship enabled. Plain `rubocop` therefore shows every existing violation, which is
the honest picture. `shipshape check` is the gate, and it is the ratchet — so adopting
the gem on a legacy app does not redden the build on day one.

## The ratchet

**There is no baseline file.** A checked-in snapshot has a regenerate button, and
pressing it on a red build is exactly what erases the signal the guard existed to
raise. The baseline is derived from git every run.

`shipshape check`:

1. finds the merge-base between `HEAD` and the trunk — configurable, defaulting to
   whatever `origin/HEAD` points at
2. adds a detached `git worktree` at that SHA
3. runs the same cop set, with the same config, in both trees
4. compares offence counts per cop

A count that rose fails, and the new offences are printed. A count that fell passes and
becomes the new floor. Results are cached by merge-base SHA, because this is two full
RuboCop runs.

**Stated limits, because a guard that hides its blind spots reads as coverage:**

- A renamed or moved file counts as new offences in the head tree and as removed
  offences in the base tree. Net-zero moves therefore pass; a move that also adds a
  violation is caught, a move that hides one is not.
- A cop added on the branch has no baseline, so every offence it finds counts as new.
  That is deliberate — a new cop starts at zero.
- It compares counts, not identities. Fixing one offence and adding another in the same
  cop nets to green.

## The rules generator

`shipshape rules` reads `docs/laws/*.md` and writes `CLAUDE.md` / `AGENTS.md` into the
folders each law binds. Each law declares its paths. The generated file carries the
statement, the reason, the guard, and the guard's limit.

Regeneration is idempotent. `shipshape rules --check` fails when a generated file is
stale, so the delivered copy cannot drift from the law.

This is the differentiator: rules delivered to the agent doing the editing, not only
checks delivered to CI.

## Compatibility

Ruby 2.7 through 3.3+, Rails 5.2 through 8. No pattern matching, no `Data.define`, no
endless methods. Forced by the older of the two intended consumers.

## Testing

**Every cop ships a test proven to fail.** Delete the guard, watch the test go red,
restore it. An unproven cop reads as coverage while catching nothing.

CI runs one command, `bin/ci`, whose steps live in the repo — so a green run locally is
a green build, and there is no second list to drift.

## Build order

Each phase stops for review before the next begins.

1. `docs/principles.md` — 6–8 principles
2. `docs/laws/` — 10–15 laws, each naming the guard it wants
3. the cops, in order of value
4. the ratchet
5. the rules generator

No cop is written for a rule the canon has not justified.

## Decisions taken

| Decision | Choice |
|---|---|
| Name | `shipshape` — free on RubyGems as of 2026-08-27 |
| Canon | written fresh, not transcribed from the existing repos |
| Layering | principle → law → guard; no separate decision layer |
| Home | `~/Development/gems/shipshape`, standalone repo |
| Publishing | local only for now |

## Open

- Which principles and which laws. That is phases 1 and 2, and it is the whole exercise.
- Whether the canon is published or stays internal. Decide once it exists.
