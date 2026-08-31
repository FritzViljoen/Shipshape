# `a-permission-is-the-class-name` — The operation's class name is the permission; there is no second name

`SettleInvoice` needs `:SettleInvoice`. The permission **is** the name, not a transform of
it — every transform is lossy, and a lossy transform collides. `FooBar` and `Foo::Bar` both
underscore to `:foo_bar`, so a grant issued for one silently runs the other. Review caught
that in code that had shipped this shape. Using the constant name is injective by
construction, which is what makes the next paragraph true.

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

**There is no constant to forget, so requiring nothing cannot happen by omission.** That is
the difference between this and a declaration: a declaration can be left out, and an omitted
permission check fails *open* — the most expensive default in software, and the one only
discovered from outside.

**An operation with no actor says so by implementing `anonymous_call`.** Login, bootstrap and
an unauthenticated upload run before anyone is identified, so there is nothing to check
against. The base class dispatches to `anonymous_call` when the class defines it, which makes
publicness a property of **the class, never of the caller** — there is deliberately no
`public_call` a caller could reach for on a guarded operation, because that would give every
privileged command an unauthenticated entry point eight characters away.
`grep -rn "def anonymous_call"` is the whole set, and it should only shrink.

An actor who is *known* but needs no grant is a different case and is not this: give it an
ordinary permission granted to everyone, so it stays in the catalogue and can still be
revoked for a suspended account.

**A nil actor raises.** It is a caller's defect, and a nil taken to mean "public" would be
the exact fail-open this law exists to prevent.

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
permitted acts is a sequence, names its steps in `call`, and is refused whole
([`a-workflow-aggregates-its-permissions`](a-workflow-aggregates-its-permissions.md)). One
permission means a command or a query; several means a workflow. The typology is not a
convention here — it is what the permission model can and cannot say.

**What this does not settle** is whether the single act you named should have been two. A
`SettleAndNotifyInvoice` has one permission, `:settle_and_notify_invoice`, and granting it
grants both halves. Nothing refuses that. What the design does is put the conflation in the
name, where a reader meets it — an operation whose name needs an "and" is usually two
operations, and now it says so on every call site.

## What an administrator grants is a capability, and it is data

A permission is fine-grained by construction — one per operation, hundreds of them — because
it is the class name and there is one class per act. An administrator does not think in
hundreds. They think in a couple of dozen buckets, configurable per tenant: *AssignWork*,
*ManageBilling*.

**Those are two different things, and only one of them is code.**

| | what it is | where it lives | how many |
|---|---|---|---|
| Permission | what the *code* requires | the class name, derived | one per operation |
| Capability | what an *administrator* grants | a row | a couple of dozen |
| The join | which permissions a capability contains | rows | authored once |

`actor.may?(permission)` resolves through the join: does any capability granted to this actor
contain this permission? **`may?` is the application's method — shipshape never sees
capabilities and needs no change to support them.** The canon says only that an operation
asks a named permission; how the actor answers is not its business.

This is also why adopting the model is smaller than it sounds. **Existing grants do not
move** — they stay on the capabilities, at the grain the business already uses. What is new
is the join, populated once, and it is data: the admin UI still shows the buckets, and a
tenant is still configured at the grain it thinks in.

**The failure mode this creates is worth guarding.** An operation contained by no capability
is unreachable — fail-closed, correct, and invisible, surfacing as a refusal nobody can
explain. Both sides are enumerable, so the check is a comparison:

```ruby
Rails.application.eager_load!   # or `descendants` answers only what has been autoloaded

missing = Permission.catalogue(Command, Query, IoCommand, IoQuery, Workflow) -
          CapabilityRecord.permissions
raise "not in any capability: #{missing.join(', ')}" if missing.any?
```

`Permission.catalogue` ships with the base classes and supplies the half shipshape can
know — every grantable permission, read off the classes, with anonymous operations left out
because they are never granted. The other half is the application's table, so the comparison
lives there.

It raises on a workflow whose `call` names no operation, deliberately: that workflow would
otherwise refuse nothing at its first real call, in production, and walking the catalogue at
boot is the cheapest place to find it.

## The catalogue is derived, never maintained

Every operation answers `permission`; every workflow answers `permissions`, read out of its
`call`.
So the full set the system recognises is read off the classes — no seed file, no registry,
nothing to fall behind the code, and no way for a permission to exist in a list but not in
the application or the reverse.

A checked-in list of permissions would be a copy of a fact the classes already state, and the
copy is the one that rots. Data holds what code cannot derive: the label, the description,
who has been granted it.

## A command does not aggregate, and the graph says which permissions are real

A command calls queries to do its work. **It does not aggregate their permissions**, and the
distinction is the one this law rests on: a workflow is the multi-permission thing, and if a
command aggregated too, the difference between them would be only that one spans transactions.
`one-operation-one-class` sizes a command so it can be permitted or refused **whole**; a
command that demanded a grant per internal read would make an internal refactor a production
authorisation change, which is how a permission model dies.

**So the command's door is the check, and a query reached from inside it is not re-checked.**
The cost is stated rather than hidden: a command *can* launder a read, returning something
derived from data the actor could not have queried directly. That is a defect in the command —
by this law's own sizing rule, one that reads salaries and cancels bookings is two operations —
and aggregation would mask it while charging every well-behaved command for it.

The consequence for the catalogue is that not every permission is grantable. An operation
reached only from inside another is never asked for a grant, so offering it on a screen is a
switch that does nothing. `CallGraph` reads the operations at boot and separates them:

```ruby
Shipshape::CallGraph.grantable(Command, Query)   # => [:CancelBooking]
Shipshape::CallGraph.internal(Command, Query)    # => [:FindBooking]
```

**The keys are class names**, which is what a label table is keyed by. "Cancel a booking" is
content — translated, edited, versioned — and belongs in a row, not in a constant.

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

- **Agreed:** Fritz, 2026-08-29 — asked how auth is handled for reads and writes, then chose the class name as the permission over a mapping.
- **Principle:** `one-way-to-say-each-thing` governs — one thing, one name.
  `make-the-wrong-thing-impossible` produces the base-class placement.
- **Guard:** the generated `permission.rb` — architecture. The permission IS `name.to_sym`,
  so there is no mapping to drift and no second name to keep in step.
- **Guard:** `Shipshape/EveryDoorChecksPermission` holds the half the base classes cannot
  hold themselves — `install` never overwrites, so an installed door that lost its check
  would disable authorisation for every operation of that kind with nothing else failing.
  The rest is held **by construction rather than by cop**: the base class runs the check for
  every operation, so there is nothing to declare and nothing to forget — the failure was
  removed rather than watched for, which is what `make-the-wrong-thing-impossible` asks. The
  generated classes are exercised by `test/shipshape/generated_base_classes_test.rb`:
  refusal, the nil-actor raise, `anonymous_call`, a workflow that sequences nothing, and the
  legacy doors.
  That is a test, not a cop, for the same bounded reason
  [`one-mechanism-guards-everything`](one-mechanism-guards-everything.md) allows `CanonTest`:
  it ships with the gem's own suite and never runs in a consuming build.
- **Guard:** the generated `call_graph.rb` and `calls.rb` — architecture. `Calls` reads a
  method's syntax tree for the operations it names, and `CallGraph` turns that into edges,
  `grantable` and `internal`. A workflow's steps are read with the same code, so a step and an
  edge are one fact found one way. Exercised by `generated_base_classes_test.rb`.
- **Guard's limit:** `CallGraph` **reads operations only, and cannot see a controller.** A
  query called both from an action and from inside a command reads as `internal` and is
  genuinely grantable, so an application must union this with what its own routes reach.
  Answering `internal` offers too few switches rather than too many, which is the safe
  direction and not the whole answer. `Calls` is syntactic: a class reached through a variable,
  `const_get` or `send` is not an edge here.
- **Guard's limit:** the base class cannot tell whether the actor it was handed is the real
  one, and nothing checks that request handling passes the requester rather than a system
  actor. It cannot see an operation invoked with `new(...).call` directly, going around
  `self.call` and therefore around the check. `EveryDoorChecksPermission` looks for the
  **call**, not for what it does: a `permits?` redefined to answer true passes, and so does
  one whose result is discarded.
