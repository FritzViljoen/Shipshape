# `no-test-factories` — A test builds state the way the application does, or the state is fiction

`create(:booking, status: "confirmed")` is a second way to construct domain state, running
beside the deeds and obeying none of their rules. No permission is checked, no arguments are
typed, no audit entry is written, and no sequence is respected. It is a private door into the
domain, held open in the one place nobody thinks of as production code.

**So a test builds what it needs by calling operations.** To have a confirmed booking, call the
deed that confirms one.

## The state a factory builds may be unreachable

This is the argument, and the rest are consequences of it.

A factory sets columns. A deed enforces the rules that decide which combinations of columns
are legal. So a factory can produce a row the application **cannot** produce — a confirmed
booking with no payment, an order line priced in a currency its order does not use — and a test
asserting behaviour on that row is asserting behaviour on fiction. It passes, it stays green
for years, and it describes a system that does not exist.

The inverse is worse and quieter. If a deed *cannot* reach a state it should, the test that
would have found it never notices, because the factory reached it instead. **The bug is in the
thing the factory replaced.**

## A factory blesses a construction; a record confesses one

`create(:booking, status: "confirmed")` reads as sanctioned. Somebody wrote that factory, it is
shared, it is what everybody uses — so a reader takes the booking it returns to be a booking.
`BookingRecord.create!(status: "confirmed", offer_id: 3, ...)` reads as what it is: somebody
stuffed columns into a row, here, in this test, and it may be nonsense.

**Both build the same fiction. Only one admits it.** That is why this law bans the factory and
not the direct write: the defect is identical, and the factory launders it into an authority.
A `create!` in a spec is ugly every time it is written, stays visible in review, and belongs to
the one test that wrote it.

## A factory is a symptom of a model nobody divided

Nobody writes a factory for a class that takes two arguments. They are necessary when making
one valid object means fifteen columns and four associations — which is what a model looks like
when it was never divided by **who may do what**. A permission is
[the class name](a-permission-is-the-class-name.md), so an operation is auth-sized; setting up
an auth-sized operation is one call, and there is nothing left for a factory to do.

So the factory is downstream of the undivided model, and removing it before the operations exist
only moves the pain. That is also why this is the **last** guard to switch on: `test_call` has
nothing to call until the deeds are there.

**The direction also runs the other way, which is why the guard is worth having at all.**
Without a factory, a god model is improbable. Nobody tolerates constructing a 113-column row by
hand, test after test — the pain lands on every test that touches it, and the model gets divided
instead. **Improbable, not impossible**: a determined author can still hand-write the columns and
a team can still tolerate it, so this is not a proof. But a factory is what removes the one force
that would otherwise have made the model's size somebody's problem — so banning it is not only
cleanup after the model is divided, it is part of what divides it.

## Setup pain is a signal, and a factory is a way of not hearing it

Fourteen calls to build one fixture says the model is wrong: too many required collaborators,
an act that cannot be expressed in one step, a missing operation nobody has written. That
message is worth having, and a factory is precisely the tool for suppressing it.

Dogfooding also means the suite exercises the operations it sets up with. A test for
`CancelBooking` that had to call `CreateBooking` first has tested both — and when it fails
because `CreateBooking` broke, that is not a cascading failure to be engineered away. It is
true.

## A test calls `test_call`, because authorisation is not the operation's behaviour

Calling operations for setup does not mean assembling a grant bag to build a booking. So
`Deed`, `Question`, `LegacyDeed` and `LegacyQuestion` carry a second entry point — every kind
that reaches a record. `IoDeed` and `IoQuestion` do not: they touch no record, so there is no
state for a test to build through them, and a test doubles the wire instead:

```ruby
booking = CreateBooking.test_call(offer_id: offer.id).value
result  = CancelBooking.test_call(booking_id: booking.id)
```

**It skips the permission check and the audit entry, and nothing else.** Typed arguments, the
transaction and the business rules all still run, so the state it produces is a state the
application can produce — which is the entire point of this law. The two it skips are the two
about the caller rather than the state: who asked, and the record that they did. A suite writing
an audit row per fixture fills the trail with rows no operator ever performed.

**And it is used on the operation under test as well, not only on setup.** A permission *is*
[the class name](a-permission-is-the-class-name.md), so authorisation here is class-sized: an
actor holds `:CancelBooking` or does not. There is no per-row rule, no per-field rule, and no
condition to get wrong — which means an operation has no authorisation behaviour of its own to
test. The check is the base class's, it is identical for every operation, and it is proven once
in the generated base classes' own suite. Re-asserting it per operation tests the framework,
and drags an actor into every test that was never about actors.

**It raises outside the test environment.** An unchecked entry point has to promise that, and a
method that exists everywhere and is merely discouraged does not. It asks `Rails.env.test?`,
which is the one ambient read in the whole shape and is on the door rather than in the work.

**That promise is why it is a second door rather than `call` with a permissive actor.** An
actor that says yes to everything is a value, and a value can be constructed anywhere,
including in production. A method that refuses to exist outside tests cannot be.

## What it costs, and it is real

Building state through deeds is slower than an `INSERT`: every setup pays typed arguments
and a transaction. On a large suite that is minutes, and this law
spends them deliberately, because a fast suite that proves the wrong thing is not a saving.

Reference data — currencies, countries, a tenant — that no operation creates is seeded, not
factoried. If nothing in the application creates a thing, a test may load it directly.

- **Principle:** `one-way-to-say-each-thing` governs — a factory is a second way to construct
  the same state, and the second way is the one that obeys no rules. `nothing-is-hidden`
  supplies the rest: a state nothing can explain is the least visible thing a suite contains.
- **Guard:** `Shipshape/NoTestFactories`, over the test trees. Fails `create`/`build`/
  `build_stubbed`/`attributes_for` on a symbol, `FactoryBot`/`FactoryGirl`/`Fabricate` by name,
  and the `fixtures` and `set_fixture_class` declarations.
- **Guard's limit:** **a record written directly is not matched, and that is deliberate.**
  `BookingRecord.create!` in a spec builds the same unreachable state a factory would, and it
  is left alone for the reason above: it confesses rather than blesses. It is also
  indistinguishable from the reference-data setup this law permits — a currency or a tenant that
  no operation creates is loaded directly — so a cop matching it would fail correct code.

  **The fixture accessors are not matched either.** `fixtures :all` is caught and `bookings(:one)`
  is not — it is an ordinary method call on an implicit receiver, and matching it would flag every
  helper a suite defines. A suite that deletes the declaration and keeps every accessor reads
  green while nothing changed.

  **It reads how state is built, never whether the state is right.** A test
  that calls the correct operations to reach a state nobody wants passes; so does one that
  reaches a legal state and asserts nothing about it.

  It matches the factory libraries it knows by name, so a helper of your own — `def
  a_booking(...)` wrapping raw `create!` — is not caught, and that is the shape a suite reaches
  for the day after this lands. **That one is a factory**: shared, curated, and blessing what it
  builds, with none of the honesty of the `create!` inside it. The rule that survives is the one
  a reader applies.

  **The message assumes `test_call` exists, and a non-auth install has none at all.**
  `test_call` is declared inside each template's `auth` branch, so `Shipshape::Install.new(auth:
  false)` renders a `Deed`, `Question`, `LegacyDeed` and `LegacyQuestion` with no second entry
  point on any of them. The cop is `Enabled: true` unconditionally and its message still reads
  `CreateBooking.test_call(...)` there — a reader on that install cannot follow it, and this law
  says nothing about what such a suite does instead. Today it has none: state is built through
  `call` with whatever actor the install lets it construct.

  **`Workflow` carries no `test_call` either, on any install — the one omission that is not
  `IoDeed`/`IoQuestion`'s.** Those two are absent from the enumeration above because they touch
  no record; `Workflow` reaches one, through its steps, so it is exactly the kind this law is
  about and it is missing anyway. The reason is its permission: `permits?` checks the union of
  every step's (`aggregate_steps`), and a workflow-level `test_call` would still have to check
  that union — reassembling the grant bag `test_call` exists to avoid. **What a test does today:
  call each step's own `test_call`, in the order the workflow's `call` runs them.** A workflow
  opens no transaction and writes no entry of its own — each step does both — so replaying the
  steps reaches the same state the workflow would have left, with no permission check in the
  chain. Whether `Workflow` should carry its own `test_call` is undecided; this states what a
  reader has today, not a recommendation.
