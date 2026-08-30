# `every-door-reports-what-it-did` — One record of every attempt, including the refused ones

Every writing door — a command, a workflow, an io command, a legacy command — records what
was attempted, by whom, and what it answered. A query does not: a read is not an attempt to
change anything, and recording every read is how an audit log becomes a log.

## It records the attempt, not the change

What changed is in the row, and `updated_at` says when. What this holds is **who asked, for
what, and what they were told** — which the row cannot say, and which is the whole of what
somebody wants on the day they ask.

**The refusal is the entry nobody has when they need it.** A caller told `:forbidden` leaves
no trace anywhere else: no row was written, nothing failed, and the only evidence the request
happened at all is here. It is recorded before the refusal is returned.

## There is one of these because every door answers the same way

This is the uniform shape paying for itself, and it is the clearest instance of what
[`an-operation-answers-a-result`](an-operation-answers-a-result.md) claims: logging,
instrumentation and an audit trail are each **one place** only because `self.call` looks
identical on every operation. Four return conventions and none of them could exist.

It is also what makes deferral possible. A deferred command has no caller to answer, so
[`deferral-is-one-command`](deferral-is-one-command.md) would otherwise be
`nothing-fails-quietly` broken by design — the receiver was never only the caller.

## After the transaction, never inside it

An entry written inside is erased by the rollback it exists to explain, so a refused or failed
attempt would leave no trace at exactly the moment a trace matters. The cost of writing it
outside is a crash between commit and record, which loses one entry. The cost of writing it
inside is losing every entry that describes a failure.

**And a broken sink does not fail the command.** The write has already committed by the time
the log runs; raising there would have the audit trail deciding the outcome of the thing it is
auditing, telling a caller its command failed when it had succeeded. The failure goes to
stderr instead — not swallowed, just not fatal.

## Arguments are not recorded

An audit log is the classic place personal data leaks: written on every call, kept longer than
the rows it describes, copied into log aggregation, and visited by no erasure request ever
written. Recording `email:` here puts a person's data somewhere
[`personal-data-is-declared-and-erasable`](personal-data-is-declared-and-erasable.md) cannot
see and nobody will delete.

An operation whose arguments genuinely belong in the trail records them itself, naming the
fields, having thought about erasure. The default is silence.

- **Agreed:** Fritz, 2026-08-30 — "during install add the audit log", after the `call_later`
  design named the missing receiver for a deferred failure as load-bearing.
- **Principle:** `nothing-fails-quietly`
- **Guard:** the generated `audit_log.rb` and the four writing doors — architecture rather
  than a cop. `self.call` records after the transaction and before answering, and the
  permission refusal records before returning. Proven by `generated_base_classes_test.rb`,
  a listed suite guard.
- **Guard's limit:** it holds the **generated** base classes, not an application's copy of
  them. `generated_base_classes_test.rb` calls every writing door and asserts an entry — for
  the success, and for the refusal — and derives the list of doors from the templates that
  contain an audit call, so a new door that records cannot ship unexercised. Each of the four
  was watched to fail by deleting its call.

  What it cannot see is a door an application has since edited: these files are installed and
  the application owns them, so `AuditLog.record` deleted there is caught by nothing —
  the same hole `Shipshape/EveryDoorChecksPermission` closes for the permission check, with no
  equivalent yet for this one.

  The sink is the application's, so what durability the trail has is not this canon's to
  claim: the default writes a line to a log, and a log is not an audit trail. It records that
  an operation was attempted and what it answered, never what it changed. And it says nothing
  about a write that reached the database by any route other than a door.
