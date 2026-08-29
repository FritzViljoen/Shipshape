# `a-permission-is-the-class-name` — The operation's class name is the permission; there is no second name

`SettleInvoice` needs `:settle_invoice`. Not because a constant says so — because the class
name is derived at the one point the check runs.

**A `PERMISSION` constant beside the class is a second name for one thing.** Two names that
*can* diverge eventually do: one gets renamed, the other does not, and nothing fails. That is
`one-way-to-say-each-thing`, and a permission is the worst place to break it, because the
divergence is silent and it grants rather than refuses.

**Uniqueness is therefore free.** Two operations cannot share a permission, because two
classes cannot share a constant. Ruby holds it. No guard has to, and the guard that would
have — scanning every operation tree for a duplicated symbol — was deleted rather than
written, which is what an abstraction earning its place looks like.

## Every operation fails closed

A new command's permission exists the moment the class does, and nobody holds a grant for it.
It is denied until someone grants it deliberately.

**There is no constant to forget, so there is no way to write an operation that requires
nothing.** That is the difference between this and a declaration: a declaration can be
omitted, and an omitted permission check fails *open* — the most expensive default in
software, and the one that is only discovered from the outside. Here the default is no, and
every exception to it is a row somebody wrote.

## This is what makes operations auth-sized, by construction

An operation has exactly one permission because it has exactly one class name. **There is no
way to express a command that spans two permitted acts** — no list, no second constant,
nowhere to put the second name. The sizing rule in
[`one-operation-one-class`](one-operation-one-class.md) stops being advice and becomes the
shape of the thing.

The pressure arrives the first time someone needs to grant half of an operation. There is no
half to grant, so the only available move is to split the class — which is the move that was
correct anyway, arriving at the moment the requirement proves it.

**A workflow is the escape hatch, and it is the only one.** Work that genuinely spans several
permitted acts is a sequence, declares its `STEPS`, and is refused whole
([`a-workflow-aggregates-its-permissions`](a-workflow-aggregates-its-permissions.md)). One
permission means a command or a query; several means a workflow. The typology is not a
convention here — it is what the permission model can and cannot say.

**What this does not settle** is whether the single act you named should have been two. A
`SettleAndNotifyInvoice` has one permission, `:settle_and_notify_invoice`, and granting it
grants both halves. Nothing refuses that. What the design does is put the conflation in the
name, where a reader meets it — an operation whose name needs an "and" is usually two
operations, and now it says so on every call site.

## The catalogue is derived, never maintained

Every operation answers `permission`; every workflow answers `permissions`, from its `STEPS`.
So the full set the system recognises is read off the classes — no seed file, no registry,
nothing to fall behind the code, and no way for a permission to exist in a list but not in
the application or the reverse.

A checked-in list of permissions would be a copy of a fact the classes already state, and the
copy is the one that rots. Data holds what code cannot derive: the label, the description,
who has been granted it.

Introspection is also what lets a caller ask before it acts — hiding a button the actor
cannot use, rather than offering it and refusing afterwards.

## Renaming an operation is a data migration, and that is the honest price

`SettleInvoice` → `SettleBooking` changes the act's name, so every stored grant of
`:settle_invoice` becomes `:settle_booking`, in a migration written and reviewed like any
other.

This is not a cost deriving introduced. It is the cost a separate constant **hides**: with a
constant, the rename looks free while the code and the granted permission quietly drift into
naming two different things. Pay it where it can be seen.

**A human-readable name is data, not a second constant.** "Settle an invoice", its
description, who it is offered to — those are columns on the permission row, edited by
whoever administers permissions, translated per locale, changed without a deploy. Putting a
display name in code would be the second name this law exists to refuse, wearing a different
hat.

## Where the check runs

In the base class, in `self.call`, before the work — never in each operation's `call`, where
it would be a line every operation has to remember and one operation will forget.

This is not a hidden callback. It is three visible statements in one method in one file that
every operation inherits, and the reader meets all of them at once. The transaction sits
there for the same reason, and shipshape's own `Command` template says why: a law held by the
base class is true by construction rather than by convention.

```ruby
class Command
  extend Permission

  def self.call(actor:, **arguments)
    return Result.failure(:forbidden) unless actor.may?(permission)

    result = ActiveRecord::Base.transaction { new(actor: actor, **arguments).call }
    ...
```

A command answers a `Result`, so refusal is a value. **A query has no envelope** — finding
nothing is an answer, not a failure — so a refused query raises `Permission::Refused`, like
every other query failure. Wrapping it would make every caller unwrap a value that was never
in doubt.

- **Principle:** `one-way-to-say-each-thing` governs — one thing, one name.
  `make-the-wrong-thing-impossible` produces the base-class placement.
- **Guard:** **none, and none is needed.** The base class runs the check for every operation,
  so there is nothing to declare and nothing to forget; the wrong thing is not discouraged,
  it is unavailable. A cop here would guard a constant that no longer exists. This is not the
  "convention, held by review" case that
  [`a-guard-states-its-limit`](a-guard-states-its-limit.md) names — it is the case that law's
  companion principle is aiming at, where the design removed the failure instead of watching
  for it.
- **Guard's limit:** the base class cannot tell whether the actor it was handed is the real
  one, and nothing checks that request handling passes the requester rather than a system
  actor. It also cannot see an operation invoked with `new(...).call` directly, going around
  `self.call` and therefore around the check —
  [`one-operation-one-class`](one-operation-one-class.md) makes `call` the only entry point,
  but nothing forbids the constructor being reached by a determined caller.
