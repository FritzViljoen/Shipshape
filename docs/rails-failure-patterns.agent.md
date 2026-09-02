# What shipshape covers — agent copy

[`rails-failure-patterns.md`](rails-failure-patterns.md) is the document — ~120 failures, each
with a verdict. This governs nothing. On conflict, the human copy wins.

The rows are not copied here. Read the row.

## The line

shipshape reads files. It sees where a rule lives, what a class may be, what the schema admits.

It does not see a page issuing 400 reads, a cache key that never expires, or a pool smaller
than the thread count. Those need a running system. Bullet, `strong_migrations`, an APM and a
load test find them.

Structural — covered. Runtime — not covered, on purpose.

## Verdicts

| verdict | for you |
|---|---|
| **Unsayable** | the shape removes it. Cannot be written inside the canon |
| **Guarded** | a cop fails the build. The row names it |
| **Procedure** | the playbook takes it apart. No cop. Judgement, with steps |
| **Uncovered** | not addressed. The row names the tool that does |

Unsayable is strongest and rarest. A cop can be disabled. A shape you cannot express cannot.

## Counting

Never quote a total from memory or from this file. Derive it:

```sh
grep '^|' docs/rails-failure-patterns.md \
  | grep -oE '\*\*(Unsayable|Guarded|Partly guarded|Procedure|Partly procedure|Uncovered)\*\*' \
  | sort | uniq -c | sort -rn
```

A count written down here drifted within a day, once. That is why there isn't one.

## Rules for you

Uncovered is not an apology and not a gap to fill. It is what makes a green `shipshape check`
mean something specific.

A green check does not mean the application is well.

## Not here

Every individual verdict. And the two gaps the exercise found — code the canon had an opinion
about and no guard for. See [`rails-failure-patterns.md`](rails-failure-patterns.md).
