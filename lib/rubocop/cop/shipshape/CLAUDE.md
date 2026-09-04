# CLAUDE.md — `lib/rubocop/cop/shipshape/`

One cop per file, flat, no subdirectories. Every cop here is checked against a real repository,
never against this one — see the root `CLAUDE.md`, "This repo is not governed by its own cops."

## A cop is not done until five things exist

1. **A law** in `docs/laws/` naming it on a `- **Guard:**` line as `` `Shipshape/YourCopName` ``.
2. **A config block** in `config/default.yml` under that same key.
3. **A `require`** for it added to `lib/shipshape.rb`.
4. **A test** at `test/rubocop/cop/shipshape/<snake_case_name>_test.rb` that (a) contains the
   literal phrase `Watched to fail` naming which real removal reddened which assertion, and
   (b) is not hidden below `private`/`protected` — a test method with those never runs and
   `test/no_hidden_test_methods_test.rb` is the only thing that would ever tell you.
5. **A canary**, planted in `test/canaries/` via `shipshape canaries --plant` and proven to
   fire — not merely present. See `test/CLAUDE.md` for what "proven" means here.
6. Named by a procedure in `docs/decomposing/*.md`, or listed in `canon_test.rb`'s
   `PROCEDURE_WOULD_NOT_HELP` with the reason nothing would move.

`test/canon_test.rb` fails the build on any of 1–4 and 6 missing; `test/removal_test.rb` and
`test/canaries_test.rb` cover 4(a) and 5 respectively — none of the three is optional, and none
substitutes for another.

## The message is the whole context an agent gets

Build every `add_offense` message through `Explains#explain(problem, because:, instead:)` (see
`explains.rb`). Three parts, always: what's wrong, `WHY:`, `INSTEAD:` with a real example.
`Shipshape/EnforcementMessagesAreDocumentation` fails a message missing either section, but it
reads sections, not sense — it will never catch a message that names a fact it did not itself
read:

- May state what the guard inspected, and what to write instead.
- **May not** state why the code came to be that way, or assert a fact about a file, class, or
  mechanism the cop did not itself read at the point it fired. "The base class already opened
  one," applied to every case when it held for two of seven, is what this looks like broken.

**The sanctioned `instead:` example is a named constant, defined above the file's first
`def on_...`.** Never a heredoc built inline where `add_offense` is called — that sits below
the matcher, so a reader stopping at the matcher never sees it.
`test/sanctioned_way_comes_first_test.rb` parses the AST for this; it is not satisfied by
"the example is somewhere in the file."

## Traps specific to writing a matcher here

- **`add_offense` dedupes by location (range) only, before anything else.** Two offences
  registered at the same range silently collapse to one — `call_graph.rb`'s own comment on a
  zero-length EOF range is the worked example: a first-byte `C.call` used to claim `(0, 1)` and
  swallow the real offence.
- **A canary proves a cop *can* fire once, never that it fires on everything the law
  describes.** A cop narrowed to the shape of its own canary passes every check this gem has —
  it has happened three times. What catches it is a case built from the law's own text, not
  from re-reading the cop or its existing test.
- **A cop that raises while computing its own offence message reports as merely "silent"** in
  `shipshape canaries`, with no hint why — `canaries_test.rb`'s crash-detection exists
  specifically because that used to read identically to a cop that never fired at all.
- **A test method under `private` or `protected` is never collected by Minitest**, and the run
  reports green. Happened twice, in different cop test files.
- Never cite by number in a law or a message — name the rule.

## Ruby floor

No pattern matching, `Data.define`, or endless methods (`required_ruby_version >= 2.7.0`,
`shipshape.gemspec`) — this file tree ships inside applications pinned well below current Ruby.
