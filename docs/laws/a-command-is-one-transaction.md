# `a-command-is-one-transaction` — A command is exactly one write, in one transaction it did not open by hand

A command does one write and the transaction around it is opened by the base class, not by
the subclass. A workflow is several commands and therefore several transactions, and it
accepts the bill for that: every step idempotent, every intermediate state legal.

**The distinction is the sharpest line in the canon.** A command that calls another command
has either nested a transaction or silently widened one, and nobody decided which. The
failure is not that it is untidy — it is that the second command's rollback semantics are now
decided by whichever caller happens to be on the stack, which is a different answer per call
site and not written anywhere.

**It is opened by the base class so it cannot be forgotten, and cannot be doubled.** Left to
each subclass, the law would be true by convention: some commands would open one, some would
not, and the ones that did would each choose their own isolation and their own rescue. One
place opening it makes the rule true by construction, and it opens *before* the work and
*after* the permission check — a refusal costs no lock.

**`return` from inside a transaction block commits it.** That is Ruby and ActiveRecord, not a
choice this canon made, and it is the one thing about the shape that regularly surprises. Work
is abandoned with `raise ActiveRecord::Rollback` and the answer given afterwards with
`failure(:code)`.

**A query opens nothing.** A read needs no transaction, and one wrapped around a read holds a
connection for no reason. The generated `Query` therefore has no transaction at all — the word
appears in that file only in a comment about the door.

- **Principle:** `make-the-wrong-thing-impossible`
- **Guard:** the generated `command.rb`, `io_command.rb` and `legacy_command.rb` — architecture
  rather than a cop. `self.call` wraps the operation in `ActiveRecord::Base.transaction`, so no
  subclass writes one and none can omit one. `Shipshape/CallGraph` holds the other half by
  refusing a command that calls a command, which is what would nest one. Proven by
  `generated_base_classes_test.rb`, a listed suite guard.
- **Guard's limit:** nothing counts the writes. A command issuing four updates is one
  transaction and passes, and whether those four are one act is a judgement no check makes. It
  cannot see a transaction opened inside a called library, and it cannot see one opened by a
  callback on a record — which is among the reasons `no-lifecycle-callbacks` exists.
