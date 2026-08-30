# `call_later` — deferring a command without loosening the canon

**Status: proposal. Nothing here is built.** Two parts need ratifying before it can be, and
both are named at the end.

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

One exception: a command may take a `Shape` (`command → shape` is in the matrix), and
ActiveJob cannot serialise one. Shapes have declared fields and value semantics, so a generic
serialiser is writable — but it is work, and it is the one part of this that is not free.

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
the first of the two things needing ratification.

## The audit log is what satisfies `nothing-fails-quietly`

A deferred failure has no caller, and a failure nobody receives is a silence. The answer is
that **every command goes through the audit log**, so the deferred failure is recorded exactly
where a synchronous one is. Deferral stops being a special case: the receiver was never only
the caller.

This is also the clearest instance of what `an-operation-answers-a-result` claims — "the
uniform answer is what makes a wrapper possible at all". One audit hook can exist because every
door answers the same way, and that same uniformity is what makes `call_later` a base-class
method rather than a per-command chore.

> **Gap: shipshape does not generate an audit log.** The base classes have no such hook today.
> The design above depends on one, so either the generated `Command` grows it or the
> application supplies it and the canon says so. This is unresolved and it is load-bearing —
> without it, a deferred failure genuinely does vanish.

## The job

One generic job, with policy declared on the command:

```ruby
class SettleInvoice < Command
  QUEUE = :payments
  RETRIES = 5
end
```

One job **execution** per command call, which is the sense of "one job per command" that
matters, while keeping application code from ever naming a job class. A job class per command
buys one extra thing — `retry_on SomeSpecificError` — which is rare enough to declare where it
is needed rather than pay for everywhere.

## What it does not solve

- **The `Shape` argument**, until a serialiser exists.
- **Permission timing.** The check runs in `self.call`. Deferred, that is *run* time, so a
  right revoked between enqueue and execution is honoured — but the caller no longer learns it
  was refused. Whether `call_later` should also check at enqueue, to fail fast, is undecided.
- **Ordering.** Two `call_later`s are two jobs with no relative order. Anything order-dependent
  is a workflow, run synchronously.
- **Nothing proves behaviour is preserved**, which is the standing gap everywhere in this
  repository and not special here.

## What needs ratifying before this is built

1. **`an-operation-answers-a-result`** — currently UNRATIFIED — with `failure` narrowed to
   *expected and terminal*, so transient conditions raise.
2. **Where the audit log lives** — generated by shipshape, or supplied by the application and
   named as a requirement by the canon.
