# Decomposing a type hierarchy — the purest case of a concept that is data

A procedure, meant to be followed by an agent one step at a time. Every step ends with
something to **run**, because a decomposition nobody can verify is a rewrite with extra
confidence.

A `type` column, or a class per variant, or both. `Payment`, `CardPayment < Payment`,
`EftPayment < Payment`, and a `payment_type` column that says which.

**This is a taxonomy written twice** — once as rows, once as classes — and the two drift. It
is the clearest example of the pattern the whole family is about, which is why it is worth
doing first if a codebase has one.

---

## 0. Make the tree visible

```sh
shipshape coverage
```

**Check:** the classes appear in `shipshape next`.

---

## 1. Separate the three things the hierarchy is doing

Almost every STI tree is doing three unrelated jobs at once. Name which is which before
moving anything, because they go to different places:

| The job | Where it goes |
|---|---|
| **Facts that differ per variant** — a rate, a label, a fee, a limit | a **row** |
| **Behaviour that differs per variant** — how a card is charged vs an EFT | a **class**, and it keeps the polymorphism |
| **Which variant this is** | a **column**, which you already have |

**Check:** you can list, for each subclass, which of its methods are constants dressed as
methods and which actually do something different.

---

## 2. Move the facts out first

This is the step that shrinks the hierarchy, and it usually removes most of it.

```ruby
# before — four classes, and the only difference is two numbers each
class CardPayment < Payment
  def fee_percentage = 2.9
  def settlement_days = 2
end
```

Those are rows in a `payment_types` table with `fee_percentage` and `settlement_days`
columns. Once they are, `CardPayment` and `EftPayment` are frequently *empty*, and the
hierarchy was never about behaviour at all.

**Check:** "Rules that are really data" falls in `shipshape report`; the subclasses shrink.

---

## 3. Ask whether any behaviour is left

If a subclass still has real behaviour after step 2 — a genuinely different algorithm — it
stays a class. But it becomes a **command or query**, not a record subclass:

```ruby
class ChargeCard < Command
  def call = success(@gateway.charge(@amount))
end

class ChargeEft < Command
  def call = success(@bank.debit(@amount))
end
```

One level from the base class, and `Shipshape/OperationsAreLeaves` holds that. The variant is
chosen at the edge — request handling picks which command to call — rather than by a record
answering questions about itself.

**Check:** `Shipshape/NoTypeInterrogation` is silent. If it still fires, something is asking
"which kind are you?" and branching, which means step 1 put a fact in the wrong column.

---

## 4. The record keeps the column and nothing else

```ruby
class PaymentRecord < ApplicationRecord
  belongs_to :payment_type_record
end
```

No `type`-based scopes carrying rules, no `card?` predicates, no subclasses.
`Shipshape/PersistenceHoldsNoBehaviour` holds this.

**Check:** the record has no methods.

---

## 5. Stop when the count stops falling

```sh
shipshape check
```

---

## What this leaves you

**Adding a variant stops being a deploy.** That is the whole return: a new payment type is a
row, and only a variant with genuinely new *behaviour* needs code — which is rare, and
obvious when it happens.

## What none of this proves

Whether two variants are really one thing with a different rate, or two things, is a
judgement and no check makes it. The signal that you got it wrong: a subclass that exists
only to hold a different constant survived step 2, or a row grew a column only one variant
uses — which is
[`a-shape-is-composed-not-flattened`](../laws/a-shape-is-composed-not-flattened.md) arriving
in the table instead.
