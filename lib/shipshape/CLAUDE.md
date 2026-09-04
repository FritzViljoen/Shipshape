# CLAUDE.md — `lib/shipshape/`

The CLI machinery: subprocess wrappers around `git` and `rubocop`, the ratchet (`check.rb`),
and the measures (`coupling.rb`, `co_change.rb`, `method_complexity.rb`, `table_shapes.rb`)
that report evidence without turning it into a verdict — `co-change-is-a-fact-not-a-verdict`
and `one-mechanism-guards-everything` both hold this: a class here that counts something is not
a guard, and must not silently become one by having a caller fail a build on its number.

## Resolve git and RuboCop config the way this tree already does — never by walking

- **`Shipshape::Git` never looks for a `.git` directory itself.** Every call passes the given
  root straight to `git -C root ...` and lets git resolve `git-common-dir` on its own — see
  `git.rb`. A tool that walks up hunting a `.git` directory treats a linked worktree's `.git`
  *file* as "not here" and keeps climbing until it reaches the main checkout, then reports
  every file's churn or diff as zero, silently, with no error. `co_change.rb` is verified
  against this gem's own two checkouts for exactly this reason; a new subprocess integration
  here must be `-C`-rooted the same way, never a directory walk.
- **`ConfigAt#call` (`config_at.rb`) resolves a target's RuboCop config via
  `RuboCop::ConfigStore#for_dir`, which performs RuboCop's own upward search from that
  directory.** When the directory handed in is a linked worktree, that search can walk past
  the worktree and pick up an ancestor's `.rubocop.yml` instead of the worktree's own — the
  same failure mode `check.rb`'s own README section on running against a pinned-RuboCop
  application already warns about needing `--config` at the repository root for. Any new
  caller of `ConfigAt` that takes a `dir:` from somewhere other than the process's own cwd
  should accept and thread through an explicit `config:` path rather than trust the walk.

## RuboCop's result cache is not neutral, and it is shared across every worktree

`~/.cache/rubocop_cache` has no per-gem-version isolation. Three distinct failures from this in
one week:

- A **recording** run (one that flips behaviour via an env var, as `coupling.rb`'s
  `RECORD_COUPLING_ENV` and `base_test_class_lines.rb`'s `RECORD_SPANS_ENV` both do) can replay
  a **plain** run's cached offences instead of actually recording, because the cache key does
  not see the env var. `coupling.rb` uses `--display-style-guide` in its command precisely
  because that flag *is* in RuboCop's `DEFAULT_PARALLEL_OPTIONS` and *is not* in `NON_CHANGING`
  — it buys the recording run its own cache bucket. `--extra-details` has the same property.
  **`--cache false` does not**: it silences caching but is absent from
  `DEFAULT_PARALLEL_OPTIONS`, so it also silently disables parallelism as a side effect.
- A stale cache entry from before a fix to what a cop records can poison every run after,
  indefinitely, because nothing ever expires it. `--no-cache`, or clearing the directory,
  rules this out when a result looks wrong for no visible reason a diff explains.

Any new subprocess call into `rubocop` from this directory that varies its own output by
something other than the file content and the config — an env var, a CLI flag RuboCop does not
already treat as cache-relevant — needs to go through this same discipline, not invent a
different one.

## Assert your own constructor arguments

Classes here `include Shipshape::TypedArguments` and call `typed(value, Type)` on constructor
arguments (see `git.rb`, `co_change.rb`) — the same runtime assertion this gem tells an
installed application to use, applied to its own code. Raise `Shipshape::Error`, not a bare
`StandardError`, for a failure a caller of this class should be able to rescue by name.

## A measure with "not built yet" as its guard is not a bug

`method_complexity.rb`, `co_change.rb`, `coupling.rb`, and `table_shapes.rb` are read by
`report.rb` and printed; none of them fails a build on its own. Wiring one of these numbers
into `check.rb` as a new pass/fail threshold is a canon decision — write the law and the
guard's limit first, not a `raise` bolted onto the measure.

## Ruby floor

No pattern matching, `Data.define`, or endless methods anywhere here
(`required_ruby_version >= 2.7.0`, `shipshape.gemspec`).
