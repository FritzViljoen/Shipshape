# Decomposing a callback web — the ordering is data nobody wrote down

`before_save`, `after_create`, `after_commit`, and a `save` that does nine things. Somewhere
a callback sets a field another callback reads, and the reason it works is the order they
were registered in.

**That order is a fact, and it exists only as the order lines appear in a file.** Nobody
chose it; it accreted. Move two lines and the behaviour changes with nothing failing.

---

## 0. Make it visible, and count what you are dealing with

```sh
shipshape coverage
shipshape report        # "Lifecycle callbacks"
```

**Check:** the record appears in `shipshape next`.

---

## 1. Write down what actually happens on save, in order

Read the registrations top to bottom and write the sequence out as a list. Include the
conditional ones (`if: :draft?`) and note what each depends on.

**This list is the thing that was never written down**, and producing it is most of the work.
Expect to find at least one callback that only works because another ran first, and at least
one that fires on an update nobody intended.

**Check:** you can state, for each callback, what must be true before it runs.

---

## 2. Separate the three kinds you will find

| What it is | Where it goes |
|---|---|
| **Normalisation** — strip, downcase, default a field | into the **command** that builds the record, or a database default's honest replacement |
| **Derivation** — set a column from other columns | a **query**, computed when asked, not stored |
| **A second effect** — send mail, enqueue a job, touch another record | its **own command**, called by name |

The third is what the law is really about. The first two are usually smaller than they look
once the third is gone.

**Check:** every callback is in exactly one row of that table.

---

## 3. Move the conditions to data if they are facts

`if: :vat_applicable?`, `unless: :internal_customer?` — a condition over a domain concept is
usually a row, not a predicate. When it is, the callback frequently disappears entirely: the
work becomes a step that applies to some rows and not others, and *which* is a column.

**Check:** "Rules that are really data" falls in `shipshape report`.

---

## 4. Make the sequence explicit, in the order you wrote down in step 1

```ruby
class ConfirmBooking < Command
  def call
    booking = BookingRecord.create!(...)   # the write
    RecalculateTotals.call(booking: booking)
    success(booking)
  end
end
```

Several steps across several transactions is a **workflow**, and it takes the bill that comes
with one: each step idempotent, each intermediate state legal, undo written as a compensating
step rather than a rollback.

**Do not port the order blindly.** The registration order was accreted; now that it is
visible, some of it is wrong and you can see which.

**Check:** `Shipshape/NoCallbacks` is silent on the record.

---

## 5. Stop when the count stops falling

```sh
shipshape check
```

---

## What this leaves you

**`save` saves.** A reader following a call sees everything that happens, and a failure is
attributed to the thing that failed rather than to the save.

## What it does not settle

Callbacks registered by a gem on your behalf stay invisible — the cop sees registration
syntax, not behaviour. And a subscriber or observer attached outside the record is a
different defect with the same shape:
[`nothing-travels-off-the-call-path`](../laws/nothing-travels-off-the-call-path.md), whose
list is also closed.
