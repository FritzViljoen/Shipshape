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

An operation has exactly one permission **of its own**, because it has exactly one class name.
There is no list, no second constant, nowhere to put a second name — so an operation cannot
declare itself to be two acts. What it *demands* is that name plus everything it reaches, and
that is derived rather than declared. The sizing rule in
[`one-operation-one-class`](one-operation-one-class.md) stops being advice and becomes the
shape of the thing: an operation is refused whole, and "whole" includes what it performs.

The pressure arrives the first time someone needs to grant half of an operation. There is no
half to grant, so the only available move is to split the class — which is the move that was
correct anyway, arriving at the moment the requirement proves it.

**Work spanning several permitted acts calls them**, and the caller demands all of them. That
is not an escape hatch and needs no kind of its own — a command reaching a query is already it.
A workflow is the kind that *only* sequences: it names its steps in `call`, is refused whole
([`a-workflow-aggregates-its-permissions`](a-workflow-aggregates-its-permissions.md)), and
contributes no name of its own because it performs no act.

**The kinds are not a permission count.** They say what a class does — a command writes, a
query reads, a workflow sequences — and every one of them demands what it reaches. A model in
which a command had a lighter rule than a workflow would need a reason why, and there is none
that survives being written down.

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

## Every operation aggregates what it reaches

**An operation that calls operations demands what they demand.** A workflow calling its steps
and a command calling a query are the same sentence, and there is one rule for both. A command
is not a smaller case with a lighter rule — a carve-out is a bug in vestments, and the version
of this law that had one lasted a day.

It is also what the doors already enforced, badly. Each operation checks on its own way in, so
an inner query refused mid-command raised *there*: a 500 after the outer check passed, where
[`an-operation-answers-a-result`](an-operation-answers-a-result.md) promises an outcome.
Aggregating moves that refusal to the door, where a refusal is what the caller gets.

**There is no third answer** for an actor short of an inner permission. Grant it, or make the
inner operation anonymous — the declaration that it needs no grant of its own. Anything else is
a case, and cases are what this law exists to not have.

The cost is stated rather than traded away: a command that gains an internal read gains a
permission, so an internal refactor can become an authorisation change. `CallGraph.routes` is
what makes that survivable — the grants each endpoint demands are derived, not remembered.

## A read that needs no grant says so, by being anonymous

The escape is the one already in the model. **A query that exists only to serve the commands
calling it implements `anonymous_call` instead of `call`** — the same declaration a login uses.
It is then never granted and never aggregated into its caller.

That keeps the choice explicit and auditable: it is a property of the class, visible in the
source, found by `grep -rn "def anonymous_call"` — never a property of the call site, where
nothing could see it. A query reachable from a controller implements `call` and is granted; one
that is part of its caller's act implements `anonymous_call` and is not.

**And anonymity is closed downward: an anonymous operation may not reach a guarded one.**
Otherwise the declaration launders everything beneath it — a login page calling a guarded
command would run that command for nobody, which is the loophole reopened one level down. An
`anonymous_call` names anonymous operations or none at all.

`Shipshape/AnonymityIsClosedDownward` fails the build on it, naming the file and the line. **It
does not raise at runtime**, deliberately: a catalogue that died on one bad declaration would
report none of the good rows, and the point of the graph is to be readable. `CallGraph.leaks`
is the same fact as data, per operation.

What an anonymous operation reaches still **aggregates upward** into a guarded caller, so
nothing is lost by passing through one.

## The catalogue knows which permissions are real

```ruby
CallGraph.grantable(Command, Query)   # => [:CancelBooking, :FindBooking]
CallGraph.unchecked(Command, Query)   # => [:LoadTenant]

CallGraph.routes
# => [{ verb: "POST", path: "/bookings/:id/cancel",
#       endpoint: "BookingsController#cancel", permissions: [:CancelBooking, :FindBooking] }]
```

Nothing is left off `grantable` for being reached from inside another operation: aggregation
means the actor holds it either way, and a screen that hid it would produce a refusal nobody
could explain. **Per endpoint is the question actually being asked** — an actor does not hold a
permission in the abstract, they hold it in order to reach something.

**The keys are class names**, which is what a label table is keyed by. "Cancel a booking" is
content — translated, edited, versioned — and belongs in a row, not in a constant.

- **Agreed:** asked how auth is handled for reads and writes, then chose the class name as the permission over a mapping.
- **Agreed:** "commands must aggregate there permissions just like
  workflows. It's a loop hole we need to close", overruling a recommendation that the command's
  door alone was the check; and "Queries should use the same anonymous_call pattern", which is
  how a read declares it needs no grant of its own.
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
- **Guard:** `Shipshape/AnonymityIsClosedDownward`, over the operation kinds. Fails an
  `anonymous_call` that names a guarded operation — the escape hatch used to launder a write.
- **Guard:** the generated `permission.rb`, `calls.rb` and `call_graph.rb` — architecture.
  `Permission#permissions` aggregates what an operation reaches and the door's private
  `permits?` demands all of it; `Calls` reads the syntax tree; `CallGraph` turns that into edges, `grantable`, `unchecked`
  and the per-endpoint rows. A workflow's steps are read by the same code, so a step and an edge
  are one fact found one way. Exercised by `generated_base_classes_test.rb`.
- **Guard's limit:** **`anonymous_call` is still a decision nothing second-guesses.** The
  closure rule stops it laundering a guarded operation, but a read that genuinely should have
  been granted, declared anonymous and reaching nothing, is unguarded and looks correct. The
  audit is `grep -rn "def anonymous_call"`, and nothing counts them for you.

  The closure cop resolves a callee to a file and reads it for `def anonymous_call`, so a
  constant resolving to no file — a gem's, or a tree the layout does not govern — is skipped
  rather than guessed at. It reads `anonymous_call` only: an anonymous operation reaching a
  guarded one through a private helper, a variable or `send` is invisible to it, exactly as it
  is to the base class.

  `Calls` is **syntactic**. A class reached through a variable, `const_get` or `send` is not an
  edge, so an operation reaching one that way demands a permission neither the aggregate nor
  the endpoint row can see — a floor, not a ceiling. An action whose work is in a
  `before_action` is invisible for the same reason the fat-controller procedure names.

  `routes` answers nothing where there is no `Rails.application` to ask, which is a fact about
  the process rather than the application. A route whose controller cannot be loaded is skipped
  rather than raised on, so a broken route is silence here.
- **Guard's limit:** the base class cannot tell whether the actor it was handed is the real
  one, and nothing checks that request handling passes the requester rather than a system
  actor. It cannot see an operation invoked with `new(...).call` directly, going around
  `self.call` and therefore around the check. `EveryDoorChecksPermission` looks for the
  **call**, not for what it does: a `permits?` redefined to answer true passes, and so does
  one whose result is discarded.
