# Decomposing a god record — the columns are several things sharing a table

113 columns, 251 public methods, and every rule about the noun lives on it. `User`,
`Booking`, `Article`, `Story` — every codebase has one, and it is the top of every report.

**The columns are the tell, not the methods.** A class can be split quietly; a table cannot.
Past the point where the noun stops explaining them, every column is a concept with nowhere
else to go.

**What you are aiming at:**

```ruby
class BookingRecord < ApplicationRecord   # the table, and nothing else
  belongs_to :supplier_record
end

class Booking < Shape                     # what travels, detached
  def initialize(reference:, supplier:, lines:)
    @reference = typed(reference, String)
    @supplier  = typed(supplier, Supplier)          # held, not flattened
    @lines     = typed_array(lines, Booking::Line)  # a part, nested
  end
end

ConfirmBooking.call(actor: actor, booking_id: id)   # the rules, one act per class
```

One table becomes a record that maps rows, a shape that travels, and one command per thing
the business does to it. The rename is what frees the name for the shape.

---

## 0. Make it visible, and find where it is reached from

```sh
shipshape coverage
shipshape next
```

A god record is reached from everywhere, so the work is bounded by call sites rather than by
the file. Expect this to take several slices; the ratchet is what makes that safe.

---

## 1. Group the columns by what changes together

Read the column list and mark which move as a set. `supplier_name`, `supplier_email`,
`supplier_phone` are one group and they are not about the booking — they are a
[flattened](../laws/a-shape-is-composed-not-flattened.md) `Supplier`.

Group by **what changes together**, not by prefix and not by type. Prefix is a hint, and
`Shipshape/ShapeIsComposed` reports it, but the question is which columns are always edited
in the same change.

**Check:** every column belongs to exactly one group, or you have found a column that is two
things.

---

## 2. Move the facts that are really data

Before extracting anything. A god record usually carries several of these:

- a `type` or `category` column with a `case` over it → a table
  ([a type hierarchy](a-type-hierarchy.md))
- a `status` column and the branches that read it → events
  ([a state machine](a-state-machine.md))
- rates, fees, limits, labels held as constants or methods → rows

**This is the step that shrinks the table**, and doing it first means the groups in step 1
stop straddling concepts.

**Check:** "Rules that are really data" and "Widest tables" both fall in `shipshape report`.

---

## 3. Take the behaviour off, one method at a time

`Shipshape/PersistenceHoldsNoBehaviour` names every method. Each becomes:

- a **query** if it reads and derives — `#total`, `#eligible?`, `#display_name`
- a **command** if it writes — `#settle!`, `#archive!`
- a **method on a shape** if it only rearranges fields it was handed — that is the one thing
  a shape may carry

"Rules that could move to a shape as they are" in the report names the third group:
methods that touch no association and no query, which are the cheapest to move and the safest
to start with.

**Check:** the record's method count falls; `shipshape check` never rises.

---

## 4. Give each group a shape, and rename the record

```ruby
class BookingRecord < ApplicationRecord   # the table, and nothing else
  belongs_to :supplier_record
end

class Booking < Shape                     # what travels, detached
  def initialize(reference:, supplier:, lines:)
    @reference = typed(reference, String)
    @supplier  = typed(supplier, Supplier)          # held, not flattened
    @lines     = typed_array(lines, Booking::Line)  # a part, nested
  end
end
```

**The rename is the point, not a side effect.** `*Record` frees the domain name for the thing
that travels, and it breaks Rails' one-model-one-table assumption on purpose — there can now
be several shapes over one table, which is what "several things sharing a table" always
needed.

**Check:** `Shipshape/CallGraph` — nothing outside a query or command reaches the record.

---

## 5. Split the table last, if at all

Only once the shapes exist and nothing reads the record directly. Often you find you do not
need to: the shapes already give each caller the columns it cares about, and the wide table
is merely ugly rather than expensive.

Split it when two groups have **different lifetimes** — written at different times, deleted
at different times, or owned by different tenants.

**Check:** "Widest tables" in `shipshape report`.

---

## What this leaves you

**A question has one place to be answered.** "What is a booking's total?" is one query, not a
method on a record reachable from every controller, view and job in the application.

## What it does not settle

Whether the columns belong together at all — the actual god-object question, and the one no
check answers. `shipshape report` counts the columns and lists the widest tables in order,
deliberately without a threshold: a line drawn there would be arbitrary, and the reader knows
which nouns their business has.
