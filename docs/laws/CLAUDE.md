# CLAUDE.md — `docs/laws/`

`README.md` beside this file is the human index — the list of laws, each pointing at its
principle. This file restates what governs *editing a law*, for whoever is handed one without
having opened the index.

## Every law file has exactly four things, and stops

What must be true; the principle it serves; the guard that holds it; the guard's limit — what a
passing run does not prove. `test/canon_test.rb` fails the build if any law is missing a
`- **Guard:**` line or a `**Guard's limit:**` section, if a Guard line names a cop that does not
exist, or if a cop exists that no law names. A law naming no guard at all and not saying
`not built yet` passes every other check vacuously — that phrase is not a formality, it is what
makes an unguarded law readable as a convention instead of silently claiming coverage it has
none of.

## Writing the guard's limit is not optional decoration

State what the guard's passing run does **not** prove — a blind spot nobody wrote down costs an
incident, not a paragraph. `a-guard-states-its-limit.md` is itself the worked example: it is the
law that requires every other law to do this, and its own limit section says its two suite
guards (`CanonTest`, `CanariesTest`) only check that the limit section and the removal claim
*exist*, never that either is true, complete, or current.

## Adding, renaming, or removing a law touches four other places

A law is one edge of a fact that also lives in `docs/laws/README.md` (the index —
`test_the_index_lists_every_law` fails if it is missing), `config/default.yml` (the cop's own
config block, if it has a guard), `lib/shipshape.rb` (the `require`), and
`docs/decomposing/*.md` (a procedure naming the cop, or `canon_test.rb`'s
`PROCEDURE_WOULD_NOT_HELP` map with the reason). Renaming a law file without touching all four
is exactly what `canon_test.rb` exists to catch — do not rename one in isolation and assume the
index will still agree.

## Never cite by number

A section mark or the word naming an ordinal position, each followed by a digit, is what this
bans. `test/documents_have_one_shape_test.rb` scans every law file for exactly that shape and
fails the build; name the rule by its own identifier instead.

## No code fence without a language tag

An unlabelled ` ``` ` fence renders unhighlighted and reads as prose — also enforced by
`documents_have_one_shape_test.rb` over this directory.

## Invariants in force here

- `#a-guard-states-its-limit`
- `#enforcement-messages-are-documentation`
