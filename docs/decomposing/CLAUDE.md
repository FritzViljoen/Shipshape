# CLAUDE.md — `docs/decomposing/`

`README.md` beside this file is the human index — one row per pattern, with what it looks like.
This file restates what governs *editing or adding a procedure*.

## Every procedure carries the same four sections, verbatim markers

`test/documents_have_one_shape_test.rb` greps every file here for: the opening line "A
procedure, meant to be followed by an agent one step at a time"; a `**What you are aiming
at:**` section; a `## What this leaves you` section; a `## What none of this proves` section.
Missing any one fails the build — an agent who has read five of these expects the same shape
from the sixth, and a procedure that only reads whole to find out whether it applies has
already cost the thing this section exists to save.

## Every step ends in something to run

A fenced `sh`/`bash` block, or a line starting `**Check:**`. `test_every_step_ends_in_
something_to_run` fails on a step with neither — "a decomposition nobody can verify is a
rewrite with extra confidence," and that line is not rhetorical, it is what the test enforces.

## A new procedure must be reachable, both directions

1. Add it to `docs/decomposing/README.md`'s table — `test_the_decomposing_index_lists_every_
   procedure` fails on a file the index does not link by its exact filename in parentheses.
2. Name every cop it walks a reader through fixing, by the cop's bare class name
   (`NoColumnDefaults`, not `Shipshape/NoColumnDefaults`) somewhere in the prose —
   `test/canon_test.rb`'s `test_every_cop_has_a_procedure_that_names_it` greps this directory's
   prose for exactly that string. A cop with no procedure and no entry in `canon_test.rb`'s
   `PROCEDURE_WOULD_NOT_HELP` map (with the reason nothing moves) is an orphan the build fails
   on.

## No industry terms in code — every procedure starts here

The one step shared by all of them, and it precedes the split rather than following it: a word
the business owns (`vat`, `gold_tier`, `draft`) is a row, not a branch. The test is who you ask
when it is wrong — a person means data, a programmer means control flow, "is it a constant?" is
the failing question. Splitting a service into fifteen classes without moving this first leaves
the branch alive in one of them; adding a value is still a deploy.

## Never cite by number, and no fence without a language tag

Both checked by `documents_have_one_shape_test.rb` over this directory, same as `docs/laws/`.

## Invariants in force here

- `#no-industry-terms-in-code`
- `#a-guard-states-its-limit`
