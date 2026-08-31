# `every-operation-reports-what-it-did` — One record of every attempt, including the refused ones

Every operation that performs an act — a command, an io command, a legacy command — records what
was attempted, by whom, and what it answered.

**A query does not**: a read is not an attempt to change anything, and recording every read is
how an audit log becomes a log. **A workflow does not either**: it performs no act, only
sequencing ones that do, and each of those records itself. An entry from the workflow would be a
second row saying that the rows beneath it happened — and the sequence is already legible from
them, in order, with the same actor on each.

## It records the attempt, not the change

What changed is in the row, and `updated_at` says when. What this holds is **who asked, for
what, and what they were told** — which the row cannot say, and which is the whole of what
somebody wants on the day they ask.

**The refusal is the entry nobody has when they need it.** A caller told `:forbidden` leaves
no trace anywhere else: no row was written, nothing failed, and the only evidence the request
happened at all is here. It is recorded before the refusal is returned.

## There is one of these because every operation answers the same way

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

## Arguments are recorded, and the personal ones are redacted

An audit log is the classic place personal data leaks: written on every call, kept longer than
the rows it describes, copied into log aggregation, and visited by no erasure request ever
written. So two things are held back, and **the first costs nobody a decision**:

1. **Anything `PersonalData` already declares.** That registry names every personal column and
   [a guard keeps it from going stale](personal-data-is-declared-and-erasable.md), so an
   argument named for one is redacted without anybody classifying it twice. A floor that
   cannot be forgotten.
2. **Anything the operation lists in `EXCLUDE_FROM_AUDIT`** — a token, a free-text note, a
   payload. For what is not a column, and so appears in no registry.

**Redacted by declaration, never by inference**, which is the same position the personal-data
law takes about columns. And a redaction keeps the argument's *name* and drops its value:
knowing an email was supplied is most of what an audit answer needs, and the value is the part
nobody can delete afterwards.

- **Principle:** `nothing-fails-quietly`
- **Guard:** the generated `audit_log.rb` and the four writing operations — architecture rather
  than a cop. `self.call` records after the transaction and before answering, and the
  permission refusal records before returning. Proven by `generated_base_classes_test.rb`,
  a listed suite guard.
- **Guard:** `Shipshape/OperationsReportWhatTheyDid`, over the installed base classes. Fails a
  writing operation's base class that no longer names `AuditLog`, once an application has an
  `audit_log.rb` to keep. The sibling of `Shipshape/EveryDoorChecksPermission`, and for the
  same reason: a generated file is the application's to edit, and one that quietly lost its
  audit call leaves no trace of anything its kind attempted while nothing else fails.
- **Guard's limit:** it holds the **generated** base classes, not an application's copy of
  them. `generated_base_classes_test.rb` calls every writing operation and asserts an entry — for
  the success, and for the refusal — and derives the list from the templates that
  contain an audit call, so a new one that records cannot ship unexercised. Each of the four
  was watched to fail by deleting its call.

  The sink is the application's, so what durability the trail has is not this canon's to
  claim: the default writes a line to a log, and a log is not an audit trail. It records that
  an operation was attempted and what it answered, never what it changed. And it says nothing
  about a write that reached the database by any route other than an operation.
