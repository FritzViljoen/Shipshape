# Decomposing — one procedure per pattern

Each file here is an ordered procedure for taking one legacy shape apart, meant to be
followed a step at a time. Every step ends in something to **run**, because a decomposition
nobody can verify is a rewrite with extra confidence.

| Pattern | What it looks like |
|---|---|
| [a service](a-service.md) | 600 lines, fifteen public methods, does everything for one noun |
| [a god record](a-god-record.md) | 113 columns, 251 methods, every rule about the thing lives on it |
| [a type hierarchy](a-type-hierarchy.md) | a `type` column, or a class per variant, or both |
| [a state machine](a-state-machine.md) | a status column and the branches that read it |
| [a callback web](a-callback-web.md) | work that happens because something was saved |

---

## The one thing they have in common

**A legacy pattern is usually a taxonomy hardcoded as code structure.**

- Single-table inheritance is a **type column** expressed as classes.
- A state machine is a **transition table** expressed as branches.
- Callbacks are an **ordering** expressed as registration order.
- A `case` over levy names is a **rate table** expressed as a method.

In each, somebody had a set of facts that grows — statuses, types, rates, steps — and no
place to put facts, so they put them in the only place Rails offered: more code. The code
then grows every time the *data* does, which is the one kind of growth refactoring never
fixes, because the code was never the problem.

**So every procedure here has the same step, and it comes before the split:** find the facts
and move them to rows. Split first and the branch survives, distributed across six classes
instead of one, still needing a deploy to add a row.

## The test for what is data

Ask who owns the fact.

- **A rate, a fee, a status the business named, a term of art, which tenant gets what** —
  somebody outside the team owns it, and changing it should not be a deploy. **Rows.**
- **A nil check, a size comparison, a retry count, whether a collection is empty** — the code
  owns it. **Control flow, and it stays.**

The failing question is "is this a constant?" — constants are code. The passing question is
"who do I ask when this is wrong?" If the answer is a person rather than a programmer, it is
data.

`shipshape report` counts the commonest shape of this under **"Rules that are really data"**:
a `case` over domain literals answering with literals. Nothing enforces it; the judgement is
the point.

## What none of these prove

**Nothing here shows the code still works.** `shipshape check` proves the offence count fell.
Every procedure assumes you write the characterisation test first — call it, record what it
answers, pin it — and `shipshape next` offers files a test names before the rest for exactly
that reason.
