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
- **Guard:** **no cop, by construction rather than by omission.** The base class runs the
  check for every operation, so there is nothing to declare and nothing to forget — the
  failure was removed rather than watched for, which is what
  `make-the-wrong-thing-impossible` asks. It is held instead by
  `test/shipshape/generated_base_classes_test.rb`, which exercises the generated classes:
  refusal, the nil-actor raise, `anonymous_call`, and the legacy doors. That is a test, not a
  cop, for the same bounded reason
  [`one-mechanism-guards-everything`](one-mechanism-guards-everything.md) allows `CanonTest`:
  it ships with the gem's own suite and never runs in a consuming build.
- **Guard's limit:** the base class cannot tell whether the actor it was handed is the real
  one, and nothing checks that request handling passes the requester rather than a system
  actor. It cannot see an operation invoked with `new(...).call` directly, going around
  `self.call` and therefore around the check. And **`shipshape install` never overwrites a
  file** — once written, `app/shipshape/command.rb` is the application's, so deleting one
  line from it disables authorisation for every command in the app and no cop, test or
  report notices. The guard is the shape of the generated code, which means it holds exactly
  as long as nobody edits it.
