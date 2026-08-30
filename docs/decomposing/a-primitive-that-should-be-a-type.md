# Decomposing a primitive — the same rule, re-derived at every call site

A procedure, meant to be followed by an agent one step at a time. Every step ends with
something to **run**, because a decomposition nobody can verify is a rewrite with extra
confidence.

The shape: `amount` is a `Float`, `state` is a `String`, `email` is a `String`, and every place
that touches one re-derives what it means — rounds it, downcases it, compares it against a
literal, formats it for a view.

**Three separate rows on any list of Rails failures are this one shape**: money as a float,
no value objects, and primitives passed everywhere. They are the same defect counted three
times.

**The canon assumes these types exist and does not tell you how to find them.**
`Shipshape/TypedArguments` makes you name a type at construction, `ShapeIsComposed` makes you
hold one rather than copy its fields, and `NoSilentCoercion` refuses the cast that would paper
over a missing one. All three are satisfied by `typed(amount, Float)` — which is the defect,
declared.

---

## 0. Find the primitives that repeat

```sh
grep -rhno "typed(\w*, \(String\|Integer\|Float\|BigDecimal\)" app | sort | uniq -c | sort -rn | head -40
```

A keyword name that appears with the same primitive type in four operations is a candidate.
One that appears once is not — a `limit:` that is an `Integer` is an integer.

**The count is the signal, not the name.** `email` in one place is a string. `email` in
eleven, each downcasing it before comparing, is a type nobody has written, and the eleventh
site is the one that forgot.

**Check:** you have a ranked list, and the top entries are nouns from the domain rather than
words like `id`, `limit` or `name`.

---

## 1. The test is whether the rule travels with the value

Ask: **when this value moves, does a rule have to move with it?**

| Value | Rule that travels | Verdict |
|---|---|---|
| `amount` | rounding, currency, "never negative", formatting | a type |
| `email` | downcase before compare, validity | a type |
| `state` | which transitions are legal | a type — and see [a state machine](a-state-machine.md) |
| `limit` | none | an `Integer` |
| `page` | none | an `Integer` |

**A primitive with no travelling rule is fine and must be left alone.** This procedure creates
types; a type per keyword argument is a worse codebase than the one you started with, and the
way to get there is to skip this step.

**Check:** none. This is the judgement the procedure exists to leave room for.

---

## 2. Money is the one to do first, and it is not a `Float`

A float cannot hold `0.1`. Two of them added and compared against a third is a bug that appears
in production, in one currency, at one total, and cannot be reproduced from the ticket.

```ruby
# the type, holding cents and a currency, because an amount without one is not an amount
class Money < Shape
  def initialize(cents:, currency:)
    @cents = typed(cents, Integer)
    @currency = typed(currency, Currency)
  end
end
```

**The column is the harder half and it is a separate change.** `decimal(19, 4)` or an integer
of minor units; never `float`. Migrating it is a data migration with a verification query, and
it does not belong in the same commit as the type.

**Check:** `grep -rn "float" db/schema.rb` returns nothing that holds money.

---

## 3. Write the type, and parse into it at the seam

The type is constructed once, at the edge, from whatever the request brought in — which is
[`input-is-parsed-at-the-seam`](../laws/input-is-parsed-at-the-seam.md) and already has a
guard. Inside, nothing re-derives anything.

```ruby
# before: every operation takes the primitive and re-derives the rule
def initialize(email:)
  @email = typed(email, String).downcase
end

# after: the rule lives once, and the operation cannot receive an unnormalised one
def initialize(email:)
  @email = typed(email, EmailAddress)
end
```

**Check:** `Shipshape/NoSilentCoercion` and `NoInlineParamParse` are silent, and the
downcasing appears exactly once in the repository.

---

## 4. Sweep the call sites, which is where this succeeds or fails

Introducing a type changes every constructor that took the primitive.
[A call-site sweep](a-call-site-sweep.md) is the procedure, and it is the largest part of this
work — not the type, which is twenty lines.

**Do not leave a compatibility shim** that accepts either the primitive or the type. That is
two ways to say one thing, it never gets removed, and the guard that would have found the
remaining call sites now passes them.

**Check:** nothing constructs the operation with the primitive; the type has no `to_s` used as
a substitute for itself.

---

## 5. Stop when the rule has one home

```sh
shipshape check
```

---

## What this leaves you

**A rule that changes in one file.** Adding a currency, tightening validity, changing how a
value formats — one place, and the compiler-equivalent (the type guard at construction) finds
the callers that no longer fit.

## What none of this proves

**The database still holds a primitive**, and every row written before the type existed was
written under the old rule. A `Money` in the application does not make the `float` column
correct, and the values already in it may not round-trip. That is a data migration with its own
verification, and this procedure does not do it.

**And a type is a place to put a rule, not proof anybody moved one.** A `Money` that is a
struct around a float, with the rounding still at eleven call sites, has added a class and
removed nothing — which is the failure mode of every value-object refactor, and the reason
step 1 is a judgement and not a grep.
