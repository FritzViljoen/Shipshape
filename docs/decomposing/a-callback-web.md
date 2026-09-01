# Decomposing a callback web — the ordering is data nobody wrote down

`before_save`, `after_create`, `after_commit`, and a `save` that does nine things. Somewhere
a callback sets a field another callback reads, and the reason it works is the order they
were registered in.

**That order is a fact, and it exists only as the order lines appear in a file.** Nobody
chose it; it accreted. Move two lines and the behaviour changes with nothing failing.

**What you are aiming at:**

```ruby
class ConfirmBooking < Command
  def call
    booking = BookingRecord.create!(...)   # the write
    RecalculateTotals.call(booking: booking)   # what a callback used to do, in order, by name
    success(booking)
  end
end
```

The ordering stops being the order lines happen to appear in a file and becomes the order they
are written in one method a reader can follow.

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

### When the effect varies per tenant, the step still runs

This is the case an automation engine gets bought for — "tenant A emails on cancel, tenant B
does not" — and it is the one that tempts a `when X, do Y` table. **Do not build one.** A rule
that fires at a command which never mentioned it is a callback with a table in front of it, and
it brings back everything this procedure just removed: an order nothing states, chains where
neither rule names the other, and work you cannot find by reading the code.

A workflow's steps are read out of its `call`, so they are fixed, and
`Shipshape/WorkflowsBranchOnOutcome` refuses `if policy.emails_on_cancel?`. Three placements
cover it, and they are the three the workflow already allows:

| The step | Where the variation lives |
|---|---|
| needs no grant from anyone — a notice the system always may send | make it **anonymous**, and it contributes no permission to the sequence |
| needs a grant, and policy decides whether it does anything | it stays a step and **no-ops convergently**, reading the policy itself |
| the sequences are genuinely different, not one sequence with a gap | **two workflows**, chosen at the edge |

**The command reads the policy; the policy does not fire the command.** That is the whole
distinction — `Finance::StatementPolicy` is pulled by the operation that decided to ask, and a
trigger table is pushed at one that did not.

**Anonymity is not a way around the permission.** It is declared on the class, for every
caller, so an operation made anonymous to keep a workflow's demands down is anonymous on the
admin screen where somebody resends it by hand. If it needs a grant there, it is not anonymous
and the second row applies.

**And the second row over-demands on purpose.** An actor running the sequence needs the fee
permission even for a tenant that never charges one, because the sequence *may* charge. If that
is wrong, the sequences were different and the third row is the answer.

**Check:** no table maps an event to an operation, and every conditional consequence is one of
the three rows.

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
different defect with the same shape —
[`nothing-travels-off-the-call-path`](../laws/nothing-travels-off-the-call-path.md), whose
list is also closed — with its own procedure: [an event bus](an-event-bus.md).
