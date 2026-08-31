# Decomposing a factory graph — a second way to build the world

A procedure, meant to be followed by an agent one step at a time. Every step ends with
something to **run**, because a decomposition nobody can verify is a rewrite with extra
confidence.

The shape: `spec/factories/`, forty definitions, `create(:booking)` pulling in an offer, a
supplier, a tenant and a currency because each declared an association. One line of setup, four
hundred milliseconds, and a row nobody can explain.

**A factory sets columns; a command enforces which combinations of them are legal.** So a
factory can build a state the application cannot, and a test asserting behaviour on that state
asserts behaviour on fiction. [`no-test-factories`](../laws/no-test-factories.md) is the law,
and `Shipshape/NoTestFactories` fails the call.

**This one is migrated, never swept.** Deleting the factory directory reddens the whole suite
at once, and a suite that is entirely red teaches nothing about which part you broke.

---

## 0. Count what depends on what

```sh
shipshape check --only Shipshape/NoTestFactories
grep -rc "create(:\|build(:" test spec | grep -v ":0$" | sort -t: -k2 -rn | head -20
```

Then read the factory definitions themselves, because the graph is there and not in the tests:

```sh
grep -rn "association\|factory :" spec/factories test/factories
```

**The associations are the finding.** `create(:booking)` that silently creates four other rows
is why the suite is slow, and it is also why nobody can say what a test's state actually is.

**Check:** you can name the three factories most tests reach for, and what each drags in.

---

## 1. Sort what the factories build into three kinds

| What it is | What replaces it |
|---|---|
| **domain state** — a booking, an order, a payment | the operations that create it, called in the test |
| **reference data** — a currency, a country, a tenant | a seed, loaded once; nothing in the application creates it |
| **a state no command can reach** | **stop.** Either the command is missing, or the test is asserting fiction |

**The third row is the point of the whole exercise.** It will not be empty, and each entry is
one of two bugs: an operation nobody wrote, or a test that has been green for years describing
a system that does not exist. Both are worth finding; neither is findable while the factory can
produce the row.

**Check:** every factory has a row, and the third row is written down as a list rather than
worked around.

---

## 2. Seed the reference data first, because everything needs it

A currency, a country, a plan, the tenant itself. No operation creates these; they are the
world the application runs in.

**Loading them directly is allowed and is not a factory.** The law is about state the
application is responsible for, and a row nothing in the application creates is not that.

**Check:** the seed loads with no factory, and a test that needs only reference data passes.

---

## 3. Replace the setup in one test file, not one factory

```ruby
# before
booking = create(:booking, :confirmed, offer: offer)

# after — the state exists because the application can produce it
booking = CreateBooking.call(actor: staff, offer_id: offer.id).value
ConfirmBooking.call(actor: staff, booking_id: booking.id)
```

**A file at a time, with the factories still present.** Both mechanisms coexist for as long as
it takes; the cop's count falls per file, and a failure is attributable to the file you just
changed.

**The setup needs an actor**, and that is not an accident — it is the test saying who is doing
this. Give it one holding the grants the setup needs, and no more: a test that sets up as an
actor with every permission has quietly stopped being able to notice a missing check.

**Check:** the file passes, and `Shipshape/NoTestFactories` is silent on it.

---

## 4. When the setup is painful, write down why before easing it

Fourteen calls to reach one fixture is a finding about the model, not about the test: too many
required collaborators, an act that cannot be expressed in one step, an operation nobody has
written.

**The wrong reflex is a test helper that wraps raw `create!`.** The cop does not catch it — a
helper of your own is not in its list — and it restores exactly what was removed, with the
audit trail of a refactor. If a helper is genuinely wanted, let it call the operations.

**Check:** every setup helper you write calls operations, and `grep -rn "create!" test spec`
returns only seeds.

---

## 5. Delete the factory when its last caller is gone

```sh
shipshape check
```

Not before. A factory with no callers is one line of deletion; a factory deleted early is a red
suite with nothing to learn from.

---

## What this leaves you

**A suite that cannot describe a system you do not have.** Every state in every test was
produced by the application, which means the tests exercise the operations twice — once as
setup and once as the thing under test — and a state that becomes unreachable breaks the tests
that relied on it, immediately and by name.

## What none of this proves

**It is slower, and that is the deliberate cost.** Every setup now pays permission checks,
typed arguments, transactions and audit entries. On a large suite that is minutes, and the law
spends them on purpose — but nothing here tells you whether your suite can afford it, and the
answer is sometimes that a hot test file needs its setup narrowed rather than its factories
back.

**And a test that calls the right operations can still assert nothing.** The cop reads how state
is built, never whether the state is the one the test needed, and never whether the assertion
that follows is worth making.
