# `a-method-carries-its-own-weight` — A method's structural cost is a number, read, not guessed

Every method has a structural cost — how much it assigns, branches on and calls — and that
cost is a number anyone can read, not something inferred by scanning the body by eye. RuboCop
already computes it: `Metrics/AbcSize`'s Assignment Branch Condition size, folding
assignments, method calls and conditions into one figure per method.

## Why ABC, and why only one number

`Metrics/CyclomaticComplexity` and `Metrics/PerceivedComplexity` count only branch and
condition nodes — `if`, `case`, `&&`, a loop. A method built from a long, branch-free chain of
calls and assignments scores near zero on either, and that shape is exactly what a real
codebase's worst methods turn out to be: `Booking#update_and_rebook`, the highest-scoring
method in a 2,011-file application by an independent measure (`flog`), is 366 points of
assignments and calls with comparatively few branches. ABC prices that shape in; Cyclomatic
and Perceived do not.

Cyclomatic and Perceived are not a second, independent view of the same method —
`PerceivedComplexity < CyclomaticComplexity`, differing only in how `case` and `if`/`else`
are weighted — so a second number bought nothing ABC did not already see. One number.

## A guard is not a report

`one-mechanism-guards-everything` already draws this line: "a measure in the report is not
enforcement and never claims to be." This is a measure. It states a method's ABC size; it
does not say a method scoring high is wrong, does not fail a build, and takes no side on
where the line between acceptable and not sits — that judgement is a human's, made with the
number in hand, not this law's to make for them.

## The number is one of a set, and cannot be optimised alone

Splitting one method into six lowers the highest per-method number while modelling nothing.
The assignments, branches and calls the original method held do not disappear — they move
into the six new methods, plus whatever the split itself now costs: an argument list carrying
what used to be a local variable, a call at each new boundary, state threaded between bodies
that used to share a stack frame. The maximum any one method now reports can fall while the
total the six of them carry together holds steady or rises.

A genuine decomposition and a metric-driven split produce the identical signature — the
per-method maximum falls — and nothing in this number tells them apart. So it is read beside
the total it was cut from, per file or per class, never chased downward by itself: a falling
maximum with a flat or rising total is the split that modelled nothing, wearing the shape of
the split that did.

- **Principle:** `nothing-is-hidden` governs — a method's true cost is written where a reader
  can see it rather than left for them to reconstruct by reading every line, and a split that
  moves the same cost into six unread places is that cost hidden again, one level down.
- **Guard:** not built yet — a report, not a ratchet. `Shipshape::MethodComplexity` reads
  every method's ABC size back from RuboCop's own `--format json`, the channel
  `BaseTestClassLines` and `Coupling` already use, and returns the numbers. Nothing consumes
  them to fail a build.
- **Guard's limit:** there is no guard, so there is nothing here for a passing run to prove
  wrong — the number is exposed, not gated, and a codebase can carry any score at all without
  `shipshape check` ever seeing it. Where a caller does read the numbers, the class reports
  ABC size only: it does not sum a file or a class total, does not rank, and does not decide
  how many methods are "too many" to have split into — the whole of the "one of a set" case
  above is a discipline for the reader, not a check this file performs. And ABC still shares
  Cyclomatic and Perceived's own blind spot on the input side: three long chained conditions
  spread across nested `unless` guards can carry less ABC than one loud `if`/`elsif` chain
  even when a reader would call the nested form harder to follow, because "harder to follow"
  and "counts more branches, assignments and calls" are related, not identical, measures.
