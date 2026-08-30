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
| [a shared concern](a-shared-concern.md) | a small module, included by nine classes, that is where their size went |
| [a query that writes](a-query-that-writes.md) | a class named `...Query` calling `create!` |
| [inline IO](inline-io.md) | `HTTParty.post` in the middle of a method, inside a transaction |
| [a generated interface](a-generated-interface.md) | a method a reader greps for and never finds |
| [a swallowed error](a-swallowed-error.md) | `rescue StandardError; nil` — a decision nobody wrote down |
| [a nullable column](a-nullable-column.md) | a gap in `db/schema.rb` that four readers read four ways |
| [a personal data trail](a-personal-data-trail.md) | erasure, which is unimplementable without an inventory |
| [a call-site sweep](a-call-site-sweep.md) | the callers of everything the procedures above moved |
| [a form that fails](a-form-that-fails.md) | the view still holds a record, and every rule here says it may not |

**A nullable column is not in a class**, which is why it is the category most often missed: a
run scoped to `app/` reports nothing about the schema, and that reads exactly like a clean one.

**"A form that fails" states the cost of adoption**, which no other procedure here does:
taking this canon all the way means the view layer stops holding ActiveRecord objects, and
Rails' view layer is built on the assumption that it does. It was written after a real
refactor hit that wall three times in one afternoon — a failure that could not carry the
invalid record, a query that must answer shapes, and `form_with model:`. If that cost is not
acceptable for an application, stopping the boundary at the controller is a legitimate answer
and pretending the cops are wrong is not.

**The last one is not like the others.** Every procedure above takes one class apart; the
sweep is one decision repeated across every caller, and it is the step that decides whether an
extraction landed or left a trail of broken callers. It is the largest single category of work
in the corpus this canon was measured against, and it is the one an agent is likeliest to
declare finished early — the cop goes quiet long before the constants reached through a string
have been found.

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
answers, pin it.

`shipshape next` makes the risk visible rather than removing it: it counts, per file, how
many methods are named anywhere in the suite and lists the ones that are not. Move the named
ones first. A method nothing mentions is one to leave until something does.
