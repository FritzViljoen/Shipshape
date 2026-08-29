# `a-workflow-aggregates-its-permissions` — A workflow names every permission its steps need, and refuses before it starts

A workflow declares `PERMISSIONS`: the union of the `PERMISSION` each operation it calls
declares. It checks the whole set before the first step, and refuses the whole workflow.

**A workflow is multi-permission by definition**, so the sizing rule in
[`one-operation-one-class`](one-operation-one-class.md) — an operation is sized so it can be
permitted or refused whole — cannot apply to it. That rule is what keeps a command honest;
a workflow is the thing that exists precisely because some work spans several permitted acts.

**And a workflow spans several transactions**, so a refusal partway cannot undo what came
before. Discovering at step three that the actor may not run step three leaves steps one and
two done, committed, and visible. There is no rollback: the transactions closed. The only
moment refusal is free is before the first step, which is why the check is there and not
distributed through the sequence.

## The check is feasibility, not authorisation

Each operation still asserts its own permission, once, where the write is
([`an-operation-declares-its-permission`](an-operation-declares-its-permission.md)). That is
the authorisation, and it stays there because an operation is reachable from a controller and
a job as well as from this workflow.

**The workflow's check is a different question**: not "may this actor do this?" but "can this
work be finished?" It refuses to start what it cannot complete. Two different questions
consulting one fact is not two places deciding — the permission model is still declared in
one place per operation, and the workflow reads it rather than restating it.

## The list is declared and derived, both

A hand-maintained list of permissions is a copy of a fact the steps already state, and a copy
rots — silently, and in the direction that grants rather than refuses, because the step
somebody added is the one missing from the list.

So the declaration is written **and** checked against the code: the guard reads what `call`
actually calls, resolves each constant to its operation, collects the `PERMISSION` each
declares, and fails when the declared set and the derived set disagree. **Where they
disagree, the list is wrong.** Adding a step to a workflow and forgetting the permission
fails the build, which is the only way this stays true.

```ruby
class SettleMonth < Workflow
  PERMISSIONS = [SettleInvoice::PERMISSION, NotifyCustomer::PERMISSION].freeze

  def initialize(actor:, month:)
    @actor = typed(actor, Actor)
    @month = typed(month, Date)
  end

  def call
    # before the first step, because after it there is nothing to refuse
    return failure(:forbidden) unless @actor.may_all?(PERMISSIONS)

    settled = SettleInvoice.call(actor: @actor, invoice_id: ...)
    return settled if settled.failure?

    NotifyCustomer.call(actor: @actor, invoice_id: ...)
  end
end
```

- **Principle:** `nothing-fails-quietly` governs — partial work with no way back is the
  quietest failure there is. `nothing-is-hidden` produces the declaration, and
  `absence-is-absence` the refusal to let a missing entry mean "allowed".
- **Guard:** `Shipshape/WorkflowAggregatesPermissions`, over the workflow kind. Fails a
  workflow with no `PERMISSIONS`, and fails one whose declared set does not match the union
  of the `PERMISSION` constants of the operations its body calls. Names the missing and the
  surplus entries separately, because they are different mistakes.
- **Guard's limit:** it reads the constants the body **names syntactically**. A step reached
  through a variable, a constant it cannot resolve to a file, or an operation called by
  another operation one level down is invisible — so the derived set is a floor, not a
  ceiling, and a workflow can still need a permission this cannot see. It does not check that
  `call` consults `PERMISSIONS`, only that the set is right, and it cannot tell whether the
  check happens before the first step or after the third. It says nothing about whether the
  actor is threaded through to each step.
