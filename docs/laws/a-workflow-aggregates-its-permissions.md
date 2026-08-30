# `a-workflow-aggregates-its-permissions` — A workflow names its steps, and refuses before it starts

A workflow declares `STEPS`: the operations it calls, in order. The base class maps each to
its permission — [the class name](a-permission-is-the-class-name.md) — checks the whole set
before the first step, and refuses the whole workflow.

`STEPS` is the one thing a workflow must declare, and only because the base class cannot see
what `call` will do until it does it. Everywhere else the permission is derived.

**A workflow is multi-permission by definition**, so the sizing rule in
[`one-operation-one-class`](one-operation-one-class.md) — an operation is sized so it can be
permitted or refused whole — cannot apply to it. That rule is what keeps a command honest;
a workflow is the thing that exists precisely because some work spans several permitted acts.

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

What is actually wanted is two reads:

- **"May this actor run it?"** — `SettleMonth.permits?(actor)`, asked by a view to decide
  whether to offer the button. One predicate, asked twice: the view asks it to offer, and
  `call` asks it to refuse. There is no second answer to get out of step with the first.
- **"What is in this bucket?"** — the coarse thing an administrator grants is data, mapped
  to the step permissions. A query and a view, not a change to the model.

## The check is feasibility, not authorisation

Each operation is still checked on its own way in, by its own base class — an operation is
reachable from a controller and a job as well as from this workflow, so that check is where
the authorisation lives.

**The workflow's check is a different question**: not "may this actor do this?" but "can this
work be finished?" It refuses to start what it cannot complete. Two different questions
consulting one fact is not two places deciding — the permission model is still declared in
one place per operation, and the workflow reads it rather than restating it.

## The list is declared and derived, both

A hand-maintained list of permissions is a copy of a fact the steps already state, and a copy
rots — silently, and in the direction that grants rather than refuses, because the step
somebody added is the one missing from the list.

So the declaration is written **and** checked against the code: the guard reads what `call`
actually calls, keeps the constants that resolve to an operation, and fails when that set and
`STEPS` disagree. **Where they
disagree, the list is wrong.** Adding a step to a workflow and forgetting the permission
fails the build, which is the only way this stays true.

```ruby
class SettleMonth < Workflow
  STEPS = [SettleInvoice, NotifyCustomer].freeze

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

- **Principle:** `nothing-fails-quietly` governs — partial work with no way back is the
  quietest failure there is. `nothing-is-hidden` produces the declaration, and
  `absence-is-absence` the refusal to let a missing entry mean "allowed".
- **Guard:** `Shipshape/WorkflowAggregatesPermissions`, over the workflow kind. Fails a
  workflow with no `STEPS`, and fails one whose declared set does not match the operations
  its body calls. Names the missing and the
  surplus entries separately, because they are different mistakes.
- **Guard's limit:** it reads the constants the body **names syntactically**. A step reached
  through a variable, a constant it cannot resolve to a file, or an operation called by
  another operation one level down is invisible — so the derived set is a floor, not a
  ceiling, and a workflow can still need a permission this cannot see. `STEPS` is read only
  as an array literal in the workflow's own body — a list built any other way reads as absent.
  Ordering is not checked: `STEPS` may list the operations in an order the body does not run
  them in. It says nothing about whether the actor is threaded through to each step.

  **A workflow's own `permission` exists but is never consulted** — the steps are what get
  granted. Granting `:SettleMonth` therefore does nothing, and nothing warns you; the coarse
  bucket an administrator grants is data, and it maps to the step permissions.
