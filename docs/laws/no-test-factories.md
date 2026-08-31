# `no-test-factories` — A test builds state the way the application does, or the state is fiction

`create(:booking, status: "confirmed")` is a second way to construct domain state, running
beside the commands and obeying none of their rules. No permission is checked, no arguments are
typed, no audit entry is written, and no sequence is respected. It is a private door into the
domain, held open in the one place nobody thinks of as production code.

**So a test builds what it needs by calling operations.** To have a confirmed booking, call the
command that confirms one.

## The state a factory builds may be unreachable

This is the argument, and the rest are consequences of it.

A factory sets columns. A command enforces the rules that decide which combinations of columns
are legal. So a factory can produce a row the application **cannot** produce — a confirmed
booking with no payment, an order line priced in a currency its order does not use — and a test
asserting behaviour on that row is asserting behaviour on fiction. It passes, it stays green
for years, and it describes a system that does not exist.

The inverse is worse and quieter. If a command *cannot* reach a state it should, the test that
would have found it never notices, because the factory reached it instead. **The bug is in the
thing the factory replaced.**

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
`Command` and `Query` carry a second entry point:

```ruby
booking = CreateBooking.test_call(offer_id: offer.id).value
result  = CancelBooking.test_call(booking_id: booking.id)
```

**It skips the permission check and skips nothing else.** Typed arguments, the transaction, the
business rules and the audit entry all still run, so the state it produces is a state the
application can produce — which is the entire point of this law.

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

Building state through commands is slower than an `INSERT`: every setup pays typed arguments, a
transaction and an audit entry. On a large suite that is minutes, and this law
spends them deliberately, because a fast suite that proves the wrong thing is not a saving.

Reference data — currencies, countries, a tenant — that no operation creates is seeded, not
factoried. If nothing in the application creates a thing, a test may load it directly.

- **Agreed:** Fritz, 2026-08-31 — "Canon governs test aswell. We dogfood our own
  implementation. No test factories", deciding that `test/` is governed rather than merely
  required to exist.
- **Principle:** `one-way-to-say-each-thing` governs — a factory is a second way to construct
  the same state, and the second way is the one that obeys no rules. `nothing-is-hidden`
  supplies the rest: a state nothing can explain is the least visible thing a suite contains.
- **Guard:** `Shipshape/NoTestFactories`, over the test trees. Fails `create`/`build`/
  `build_stubbed`/`attributes_for` on a symbol, `FactoryBot`/`FactoryGirl`/`Fabricate` by name,
  and the `fixtures` and `set_fixture_class` declarations.
- **Guard's limit:** **the fixture accessors are not matched.** `fixtures :all` is caught and
  `bookings(:one)` is not — it is an ordinary method call on an implicit receiver, and matching
  it would flag every helper a suite defines. A suite that deletes the declaration and keeps
  every accessor reads green while nothing changed.

  **It reads how state is built, never whether the state is right.** A test
  that calls the correct operations to reach a state nobody wants passes; so does one that
  reaches a legal state and asserts nothing about it.

  It matches the factory libraries it knows by name, so a helper of your own — `def
  a_booking(...)` wrapping raw `create!` — is not caught, and that is the shape a suite reaches
  for the day after this lands. `Record.create!` called directly in a test is likewise not
  matched: distinguishing it from the same call inside a legitimately seeded reference row
  needs a judgement no cop makes. The rule that survives is the one a reader applies.
