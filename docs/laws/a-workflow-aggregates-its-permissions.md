# `a-workflow-aggregates-its-permissions` — A workflow names its steps, and refuses before it starts

A workflow's steps are the operations its `call` names, in order. The base class reads them
out of `call`, maps each to its permission — [the class name](a-permission-is-the-class-name.md)
— checks the whole set before the first step, and refuses the whole workflow.

Nothing is declared. `RubyVM::AbstractSyntaxTree.of` hands back the syntax tree of `call`
itself, so the list is derived from the only copy there is.

**This is not special to workflows.** Every operation demands what it reaches
([`a-permission-is-the-class-name`](a-permission-is-the-class-name.md)) — a command calling a
query aggregates exactly the same way. The sizing rule in
[`one-operation-one-class`](one-operation-one-class.md) still holds and is not weakened by it:
an operation is refused **whole**, and aggregation is what makes "whole" mean the act plus
everything the act performs.

What is left to a workflow is one property, and it is a statement about what a workflow is
rather than an exemption from the rule: **it contributes no permission of its own.** Granting
`:SettleMonth` does nothing, because a workflow performs no act — it only sequences the acts
that do.

**And a workflow spans several transactions**, so a refusal partway cannot undo what came
before. Discovering at step three that the actor may not run step three leaves steps one and
two done, committed, and visible. There is no rollback: the transactions closed. The only
moment refusal is free is before the first step, which is why the check is there and not
distributed through the sequence.

## An anonymous step contributes nothing

An operation implementing `anonymous_call` is never granted — that is what anonymous means —
so aggregating its name would demand a grant nobody can hold, and the workflow containing it
would be permanently forbidden. `permissions` skips them.

**A workflow all of whose steps are anonymous is itself anonymous**, and says so the same way
an operation does, by implementing `anonymous_call`. A signup sequence — create the account,
log in, send the welcome — runs before anyone is identified, and demanding an actor for it
would make the sequence inexpressible.

## Granting the workflow as a unit is a read problem, not an authorisation one

The urge is real — an administrator thinks in "may they close the month", not in seven step
permissions. But a workflow that **overrode** its steps would need an unchecked path into
each command, and a command reachable unchecked is reachable unchecked by anyone who finds
that path. That is the same hole `anonymous_call` exists to avoid giving callers, so
authorisation stays the AND of the steps, with no override.

What is actually wanted is a read: **"what is in this bucket?"** — the coarse thing an
administrator grants is data, mapped to the step permissions. A query and a view, not a change
to the model.

**And not a predicate a view may ask.** `permits?` is private, because the only reason to ask
is to branch, and a decision has one home. A page offers the action and places the refusal that
comes back, or it is handed a shape whose fields already say what is offerable — computed by
the query that built it, which is an operation and may decide.

## The check is feasibility, not authorisation

Each operation is still checked on its own way in, by its own base class — an operation is
reachable from a controller and a job as well as from this workflow, so that check is where
the authorisation lives.

**The workflow's check is a different question**: not "may this actor do this?" but "can this
work be finished?" It refuses to start what it cannot complete. Two different questions
consulting one fact is not two places deciding — the permission model is still declared in
one place per operation, and the workflow reads it rather than restating it.

## The list was declared once, and the declaration is what rotted

A workflow declared a `STEPS` constant for a while, with a guard checking it against what the
body called. That is a copy of a fact the steps already state, and a copy rots — silently, and
in the direction that grants rather than refuses, because the step somebody added is the one
missing from the list. The guard held the two in step, but there were still two places to
change and one of them was easy to forget.

Reading `call` removes the second copy rather than policing it, which is what
[`one-way-to-say-each-thing`](one-way-to-say-each-thing.md) asks for: an abstraction earns its
place by removing a way to say something.

**Only `call` is read, and that is a constraint worth having.** A workflow *is* a sequence; a
step hidden behind a private helper is a sequence that does not read as one.

**But an unread step fails open, and saying so is not enough.** Fewer steps found means fewer
permissions demanded, and the dangerous case is not the workflow that reads as empty — that one
raises. It is the workflow with one step in `call` and another behind a helper: the reading
finds a step, raises nothing, and demands half of what the workflow owes. The build is green
and the refusal arrives at step two, after step one has committed.

So the guard fails the shapes the reading cannot see, rather than describing them:
a receiver that is not a constant, and an operation called from any method other than `call`.
The reading and the guard recognise exactly the same shapes, which is the only arrangement in
which the green build means anything.

```ruby
class SettleMonth < Workflow
  def initialize(month:)
    @month = typed(month, Date)
  end

  # `Workflow.call` has already refused if the actor may not run every step.
  def call
    settled = SettleInvoice.call(actor: actor, invoice_id: ...)
    return settled if settled.failure?

    NotifyCustomer.call(actor: actor, invoice_id: ...)
  end
end
```

- **Agreed:** Fritz, 2026-08-29 — "we also need a way to aggregate permissions for workflows".
- **Principle:** `nothing-fails-quietly` governs — partial work with no way back is the
  quietest failure there is. `nothing-is-hidden` produces the declaration, and
  `absence-is-absence` the refusal to let a missing entry mean "allowed".
- **Guard:** `Shipshape/WorkflowAggregatesPermissions`, over the workflow kind. Fails three
  shapes, all of them permissions never demanded: a `call` naming no operation the layout
  knows; a `call`/`call_later` receiver that is not a constant; and an operation called from
  any method other than `call`. The base class raises on the first; the cop moves all three
  off the first production call.
- **Guard's limit:** it reads constants **syntactically**, the same way the base class does,
  so a step reached through `const_get`, `send`, or a constant assigned from a variable is
  invisible to both — and unlike the shapes above, invisible without being reported. That is
  a fail-open: the workflow demands less than it owes and nothing says so. A constant
  resolving to no governed file is skipped, which is right for a `Proc` in a constant and
  wrong for an operation the layout does not cover. Ordering is not checked, nor whether a
  named constant is called rather than merely mentioned, nor whether the actor is threaded
  through to each step.

  **`RubyVM` is MRI's.** On an interpreter without it the reading raises rather than
  answering `[]`, which is the fail-closed direction, but it means the base class as written
  does not run there.

  **A workflow's own `permission` exists but is never consulted** — the steps are what get
  granted. Granting `:SettleMonth` therefore does nothing, and nothing warns you; the coarse
  bucket an administrator grants is data, and it maps to the step permissions.
