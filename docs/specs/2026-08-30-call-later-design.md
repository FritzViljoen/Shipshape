# `call_later` — deferring a command without loosening the canon

**Status: built, 2026-08-30.** One part still needs ratifying and is named at the end.

Origin: refactoring `MessagesController#create` in lobsters found that `perform_later` had no
legal home in any kind — no matrix row permits calling an `entry_point`, correctly, and every
Rails application defers work. An agent's first fix was a `Schedules` row on the call graph,
which loosened the canon to fit the problem and was reverted. This is Fritz's fix, which does
not.

---

## What it is

```ruby
SettleInvoice.call(actor: actor, invoice_id: 1)        # now
SettleInvoice.call_later(actor: actor, invoice_id: 1)  # one job, one transaction
```

`call_later` goes on the writing doors — `Command`, `IoCommand`, `LegacyCommand`. Not `Query`,
which would answer nothing to nobody. Not `Workflow`: a workflow spans several transactions,
so one job holding three of them retries steps that already committed. **Deferral belongs to
the steps, never to the sequence.**

## Why it needs no change to the call graph

`perform_later` appears exactly twice — in the base class and in one generic job, both under
`app/shipshape/`, which every cop already excludes. **Application code never names a job
class.** That is the whole reason this beats a matrix row: the rule "nothing may call an entry
point" stays true and absolute, and the capability arrives underneath it rather than through a
hole cut in it.

## Why the arguments already serialise

ActiveJob needs primitives. The canon already requires them: *a record is not an argument*
(`arguments-are-typed-at-construction`), so every command's inputs are ids and values before
anybody thought about queues. **The capability was paid for by an existing rule.**

**A `Shape` argument is the one thing ActiveJob cannot carry.** A hand-rolled packer sat here
briefly and was deleted: it was a second, worse copy of `ActiveJob::Arguments`, which already
round-trips symbol keys, nesting and dates exactly — and the copy arrived with a key-fidelity
bug ActiveJob does not have and a `const_get` on a queue payload it would never have invited.

`Shape#to_h` is what replaced it. A shape is a hash with a declared shape, so `to_h` is that
hash and `new(**shape.to_h)` is the round trip. A caller deferring an operation that takes a
shape hands the hash; **a command whose initializer demands the shape itself cannot be
deferred**, and fails at enqueue with ActiveJob's own error naming the type. Commands take ids
and values, so that is rare — and if it stops being rare, an `ActiveJob::Serializers`
registration is the supported answer.

## The contract with `an-operation-answers-a-result`

The law's mechanism is *the caller receives the outcome as a value*, and a deferred run has no
caller. It reconciles without a new taxonomy if two things hold:

**1. A deferred command answers `success` on a repeat.** Not `failure(:already_settled)`. The
operation's job was "make this settled"; it is settled; that is what was asked for. `already_X`
reports a **state**, not a failure of the operation — and to a machine retry it is poison,
because the job dead-letters on an outcome that succeeded. This falls out of
`a-command-runs-twice`, so the two lock together.

**2. `Result` failure means expected _and terminal_.** Re-running will not change it. Then:

| Outcome | The job does |
|---|---|
| `success` | finish |
| `failure(:code)` | record it, finish, **do not retry** |
| raise | let the queue retry |

A transient condition — a gateway timeout — therefore **raises** rather than answering
`failure(:gateway_unavailable)`. That is a narrowing of what the law permits today, and it is
the one thing still needing ratification.

## The audit log is what satisfies `nothing-fails-quietly`

A deferred failure has no caller, and a failure nobody receives is a silence. The answer is
that **every command goes through the audit log**, so the deferred failure is recorded exactly
where a synchronous one is. Deferral stops being a special case: the receiver was never only
the caller.

This is also the clearest instance of what `an-operation-answers-a-result` claims — "the
uniform answer is what makes a wrapper possible at all". One audit hook can exist because every
door answers the same way, and that same uniformity is what makes `call_later` a base-class
method rather than a per-command chore.

This was a gap when the note was written — shipshape generated no audit log, and without one
a deferred failure genuinely vanished. `shipshape install` now writes `audit_log.rb` and every
writing door reports to it, including the refusals.

## The job

One generic job, with policy declared on the command:

```ruby
class SettleInvoice < Command
  QUEUE = :payments
  ATTEMPTS = 5
end
```

One job **execution** per command call, while keeping application code from ever naming a job
class.

**`ATTEMPTS` works per operation from a single job class**, which an earlier draft of this note
said was impossible. `retry_on` captures its `attempts:` when the job class is defined, so it
would fix one policy for every command — but writing the retry out instead reads the number at
the moment the decision is made:

```ruby
rescue StandardError => error
  raise error if executions >= attempts_for(operation)

  retry_job(wait: backoff)
end
```

`executions` is ActiveJob's own count, so nothing keeps a second tally. What a job class per
command would still buy is `retry_on SomeSpecificError` — a different policy per exception
type — which is rare enough to declare where it is needed.

## What it does not solve

- **Permission timing is settled: checked twice.** At enqueue, so the caller learns
  immediately and gets `failure(:forbidden)` synchronously; and again in `self.call` when the
  job runs, because a right revoked in between is the answer that matters. Both refusals are
  audited.
- **Ordering.** Two `call_later`s are two jobs with no relative order. Anything order-dependent
  is a workflow, run synchronously.
- **Nothing proves behaviour is preserved**, which is the standing gap everywhere in this
  repository and not special here.

## Settled since this was written

**The audit log lives in `shipshape install`.** Every writing door reports to it, so a deferred
failure is recorded exactly where a synchronous one is and `nothing-fails-quietly` is satisfied
without a caller.

## What still needs ratifying

**`an-operation-answers-a-result`** — currently UNRATIFIED — with `failure` narrowed to
*expected and terminal*, so transient conditions raise rather than answering
`failure(:gateway_unavailable)`. The job depends on that split: a raise retries, a failure does
not. It is built on that assumption and the assumption is not yet law.
