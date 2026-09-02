# `a-write-is-one-transaction` — One transaction, opened by the base class, however many writes it holds

**A write may write as many rows to as many tables as one act needs** — an invoice and its
lines, an order and its items, a row and the counter that follows it. What it may not do is
span more than one transaction, and the transaction is opened by the base class rather than
by the subclass.

The unit is the **act**, not the row. A workflow is several writes and therefore several
transactions, and it accepts the bill for that: every step idempotent, every intermediate
state legal.

**The distinction is the sharpest line in the canon**, and it is about atomicity rather than
tidiness. A write that calls another write has either nested a transaction or silently
widened one, and nobody decided which — so the second write's rollback semantics are now
decided by whichever caller happens to be on the stack, which is a different answer per call
site and written nowhere.

**Four writes inside one write are not a smell.** They either all happen or none do, which
is the whole point of the transaction being there. Four writes across two writes called in
sequence is the defect, because the middle state is reachable and nobody said what it means.

**It is opened by the base class so it cannot be forgotten, and cannot be doubled.** Left to
each subclass, the law would be true by convention: some writes would open one, some would
not, and the ones that did would each choose their own isolation and their own rescue. One
place opening it makes the rule true by construction, and it opens *before* the work and
*after* the permission check — a refusal costs no lock.

**`return` from inside a transaction block commits it.** That is Ruby and ActiveRecord, not a
choice this canon made, and it is the one thing about the shape that regularly surprises. Work
is abandoned with `raise ActiveRecord::Rollback` and the answer given afterwards with
`failure(:code)`.

**A read opens nothing.** A read needs no transaction, and one wrapped around a read holds a
connection for no reason. The generated `Read` therefore has no transaction at all — the word
appears in that file only in a comment about the door.

- **Principle:** `make-the-wrong-thing-impossible`
- **Guard:** the generated `write.rb` and `legacy_write.rb` — architecture rather than a
  cop. `self.call` wraps the operation in `ActiveRecord::Base.transaction`, so no subclass
  writes one and none can omit one. `Shipshape/CallGraph` holds the other half by refusing a
  write that calls a write, which is what would nest one.
  `Shipshape/OperationsOpenNoTransaction` refuses a `transaction` send written inside any
  operation kind — catching a second one opened directly in `write` and `legacy_write`,
  one opened where a workflow's steps should each own their own, one held open over the wire
  in `io_write` and `io_read`, and one wrapped around a read that needs none in `read` and
  `legacy_read`. Proven by `generated_base_classes_test.rb`, a listed suite guard.
- **Guard's limit:** nothing counts the writes, and nothing should — the number is not the
  rule. **What no check makes is the judgement of whether those writes are one act**: a
  write updating an invoice and archiving an unrelated report is two acts sharing a
  transaction, and it passes everything here.

  It cannot see a transaction opened inside a called library, and it cannot see one opened by
  a callback on a record — which is among the reasons `no-lifecycle-callbacks` exists.
  `Shipshape/OperationsOpenNoTransaction` sees only a *send named `transaction`*: one opened
  through a helper method, or by a gem calling back into the operation, is invisible to it.
  So is one opened on a record **instance** rather than the class: `@booking.transaction do
  ... end` reaches the same `ActiveRecord::Transactions#transaction`, and the matcher only
  roots a bare call or a call on a resolvable constant — an instance variable is neither, so
  it passes unrefused.

  **It also over-catches.** The matcher refuses a `transaction` send with a block that is
  either bare or rooted in a record constant — `ActiveRecord::Base` included — so a same-named
  method on something that is not a record is a false positive to be argued in review: a
  payment gateway's own `#transaction` API, a `transaction` association, an `attr_reader`
  named `transaction`. Attaching a block to one of those and rooting it in a record-looking
  constant this configuration does not resolve would still slip through unrefused.
