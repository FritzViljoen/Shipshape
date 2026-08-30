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
| [a fat controller](a-fat-controller.md) | an action that parses, finds, checks, branches, writes and renders |

---

## No industry terms in code

**A word the business owns is a row, not a branch.** `vat`, `tourism_levy`, `gold_tier`,
`draft`, `card_payment` — if somebody outside the team owns the word, it belongs in the
database. That is [`no-industry-terms-in-code`](../principles.md), and **every procedure here
starts with it.**

The test is who you ask when it is wrong. A person — an accountant, an operations manager,
the client — means data. A programmer means control flow, and it stays. "Is it a constant?"
is the failing question, because constants are code.

**Each pattern below is the same defect in a different costume:**

| The pattern | The industry term, written as code |
|---|---|
| single-table inheritance | a **type column**, written as classes |
| a state machine | a **transition table**, written as branches |
| lifecycle callbacks | an **ordering**, written as registration order |
| a `case` over levy names | a **rate table**, written as a method |

A fat controller is the exception: its defect is misplacement rather than a term written as
code, which is why it is the one procedure that does not begin with the data step. It is also
rarely the cheapest place to start — the rules it branches on usually live on a record, so
[a god record](a-god-record.md) comes first or the extracted command wraps the same god
object.

Each began the same way: a set of facts that grows — statuses, tiers, rates, steps — and no
place to put facts, so they went where the framework offered room, which was more code.

**This is why it comes before the split.** Code that encodes facts grows every time the facts
grow, and refactoring never fixes that, because the code was never the problem. Split a
fifteen-method service into fifteen classes and the branch survives in one of them — adding a
levy is still a deploy.

`shipshape report` counts the commonest shape under **"Rules that are really data"**: a `case`
over domain literals answering with literals. Nothing enforces it; the judgement is the point.

## What none of these prove

**Nothing here shows the code still works.** `shipshape check` proves the offence count fell.
Every procedure assumes you write the characterisation test first — call it, record what it
answers, pin it — and `shipshape next` offers files a test names before the rest for exactly
that reason.
