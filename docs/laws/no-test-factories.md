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

## What it costs, and it is real

Building state through commands is slower than an `INSERT`: every setup pays permission checks,
typed arguments, transactions and audit entries. On a large suite that is minutes, and this law
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
  and Rails fixtures — `fixtures :all` and the accessors it generates.
- **Guard's limit:** **it reads how state is built, never whether the state is right.** A test
  that calls the correct operations to reach a state nobody wants passes; so does one that
  reaches a legal state and asserts nothing about it.

  It matches the factory libraries it knows by name, so a helper of your own — `def
  a_booking(...)` wrapping raw `create!` — is not caught, and that is the shape a suite reaches
  for the day after this lands. `Record.create!` called directly in a test is likewise not
  matched: distinguishing it from the same call inside a legitimately seeded reference row
  needs a judgement no cop makes. The rule that survives is the one a reader applies.
