# Decomposing — one procedure per pattern

Each file here is an ordered procedure for taking one legacy shape apart, meant to be
followed a step at a time. Every step ends in something to **run**, because a decomposition
nobody can verify is a rewrite with extra confidence.

| Pattern | What it looks like |
|---|---|
| [a service](a-service.md) | 600 lines, fifteen public methods, does everything for one noun |
| [a god record](a-god-record.md) | 113 columns, 251 methods, every rule about the thing lives on it |
| [a scope chain](a-scope-chain.md) | `Story.where(...).joins(...).order(...)` — a query nobody named |
| [characterise the edges](characterise-the-edges.md) | **do this first** — the tests that survive every procedure above |
| [a type hierarchy](a-type-hierarchy.md) | a `type` column, or a class per variant, or both |
| [a state machine](a-state-machine.md) | a status column and the branches that read it |
| [a stored derivation](a-stored-derivation.md) | a column the database could work out for itself — and three of the four reasons it is right |
| [a callback web](a-callback-web.md) | work that happens because something was saved |
| [a fat controller](a-fat-controller.md) | an action that parses, finds, checks, branches, writes and renders |
| [a filter chain](a-filter-chain.md) | six `before_action`s and three-line actions — the work moved above them |
| [an unowned find](an-unowned-find.md) | `Story.find(params[:id])` — the row exists, so it was returned |
| [an unbounded read](an-unbounded-read.md) | a query with no answer to "how many?" — no page, no limit, no cursor |
| [work in the request cycle](work-in-the-request-cycle.md) | the caller waiting for four things they cannot see |
| [an untimed call](an-untimed-call.md) | somebody else's outage, arriving as yours |
| [a shared concern](a-shared-concern.md) | a small module, included by nine classes, that is where their size went |
| [a record concern](a-record-concern.md) | a module that obliges every table including it to carry its columns |
| [a query that writes](a-query-that-writes.md) | a class named `...Query` calling `create!` |
| [inline IO](inline-io.md) | `HTTParty.post` in the middle of a method, inside a transaction |
| [a generated interface](a-generated-interface.md) | a method a reader greps for and never finds |
| [a swallowed error](a-swallowed-error.md) | `rescue StandardError; nil` — a decision nobody wrote down |
| [a nullable column](a-nullable-column.md) | a gap in `db/schema.rb` that four readers read four ways |
| [an unindexed foreign key](an-unindexed-foreign-key.md) | `t.bigint "order_id"` with no index — the join the database has to scan |
| [a serialized column](a-serialized-column.md) | a JSON or YAML blob holding eleven keys nothing declares |
| [a polymorphic association](a-polymorphic-association.md) | `commentable_type` — a class name in a data column, with no foreign key |
| [a primitive that should be a type](a-primitive-that-should-be-a-type.md) | `amount` as a float, `state` as a string, the rule re-derived at every call site |
| [an enum as an array](an-enum-as-an-array.md) | the column holds a position, so reordering the source rewrites the data |
| [a feature flag](a-feature-flag.md) | a branch with no owner and no expiry, doubling the state space |
| [a personal data trail](a-personal-data-trail.md) | erasure, which is unimplementable without an inventory |
| [a call-site sweep](a-call-site-sweep.md) | the callers of everything the procedures above moved |
| [a form that fails](a-form-that-fails.md) | the view still holds a record, and every rule here says it may not |

**A nullable column is not in a class**, which is why it is the category most often missed: a
run scoped to `app/` reports nothing about the schema, and that reads exactly like a clean one.

**A scope chain is the commonest shape here by some distance** — 1,600 of them against 952
declared scopes across seven codebases — and the one least often treated as a decomposition
at all. It is also where the call graph is already half-shouting: the controller chains are
refused today, and the model and service ones, which are the larger half, are legal and
unnamed.

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

## Start from the transaction blocks — somebody already drew the boundary

**A command is one transaction** ([`a-command-is-one-transaction`](../laws/a-command-is-one-transaction.md)),
however many writes that holds. Read backwards, that is a finding technique: every
`transaction do` already in the codebase is a place where somebody decided *these writes are
one act*, and that decision is a command waiting to be named.

```sh
grep -rn "transaction do\|transaction {" app lib | grep -v spec
```

**This is the cheapest list in the whole playbook, and it is not a guess.** Most refactoring
heuristics infer a boundary from shape — method length, coupling, a noun that appears a lot.
This one reads a boundary somebody wrote down, under pressure, because getting it wrong
corrupted data. Whatever else is unclear about the code, the author was sure about that.

**Take the whole block, not the method around it.** The block's contents are the command's
`call`; what precedes it is the caller's business — parsing, finding, deciding — and belongs
where the procedure for that shape says.

**Measured across six public Rails codebases: 307 blocks**, and where they sit is the useful
part — the list is ordered by what the corpus actually holds, not by what one would guess:

| Where it is | How many | What it is |
|---|---|---|
| a **model** method | 98 | a god record doing the work — [a god record](a-god-record.md) first, and the block is the command that comes out |
| a **service** method | 89 | a command, and the rest of the method is its caller — [a service](a-service.md) |
| a **controller** action | 60 | the action's whole job — [a fat controller](a-fat-controller.md) |
| a **job** or elsewhere | 60 | usually a command with a doorbell attached |

A transaction wrapping **two** unrelated acts is two commands, and the warning below applies.
One with an HTTP call inside it is [inline IO](inline-io.md), and urgent.

**The model bucket being the largest is the finding.** A transaction inside a record is a
record deciding what is atomic, which is behaviour on a thing that should map rows —
`persistence-holds-no-behaviour` and this technique point at the same files from opposite
directions.

**The two-act case is the one that costs something, and it must be said out loud.** Splitting
one transaction into two commands means the middle state becomes reachable: the first
committed, the second did not. That state was always *possible* — a crash could produce it —
but it was rare, and afterwards it is ordinary. So a workflow sequences them, every step is
idempotent, and somebody decides what the half-done state means. **If nobody will do that
work, leave the transaction alone**: one command doing two acts is a smell, and two commands
with an unconsidered gap between them is a bug.

**A nested transaction is not the savepoint it looks like.** Rails' default reuses the outer
one, so an inner `transaction do` neither isolates nor rolls back on its own — which is
exactly the ambiguity `a-command-is-one-transaction` refuses when it forbids a command calling
a command. An inner block is usually a command that was already extracted in someone's head.

**Check:** every block on the list is either a command now, or has a sentence next to it
saying why it is not.

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

## Before any of them: characterise the edges

**Nothing any procedure here does proves the code still works.** `shipshape check` proves the
offence count fell.

[Characterising the edges](characterise-the-edges.md) is the answer and it comes first.
**Treat the repository as a black box**: every procedure below moves internals, so a test
written against an internal is deleted by the extraction it was meant to protect. The edges —
a request, a job — are what a refactor must not change, which is what makes them the only
place a test survives the work.

```sh
shipshape edges     # the ones nothing in the suite names
```

## What none of these prove

Even with the edges recorded: these procedures move code, and a green count is not a working
application.

`shipshape next` makes the risk visible rather than removing it: it counts, per file, how
many methods are named anywhere in the suite and lists the ones that are not. Move the named
ones first. A method nothing mentions is one to leave until something does.
