# `deferral-is-one-command` — Work is deferred one command at a time, or not at all

`SettleInvoice.call_later(actor: actor, invoice_id: 1)` puts **one command** on a queue: one
transaction, one job. A retry therefore re-runs exactly one transaction, which is the only
grain at which a retry is safe.

## Not a workflow, and not a query

A workflow spans several transactions. One job holding three of them retries steps that
already committed, so deferral belongs to the steps and never to the sequence. A query
answers shapes to a caller, and a deferred query answers nothing to nobody.

So `call_later` exists on the writing operations alone — and the guard that admits it is
told which kinds those are. Putting it on a flat list of permitted messages let `SomeWorkflow.call_later`
pass the build and fail in production with `NoMethodError`, which is a guard moving a failure
rather than catching one.

## A retry is safe because of a law, not a hope

[`a-command-runs-twice`](a-command-runs-twice.md) already obliges every command to survive a
second call: a caller may not ask whether the work has happened, because branching is asking,
so the command owns repetition itself. Deferral is what turns that from tidy into
load-bearing — a queue retries on a timeout, a deploy, a worker restart, and a command that
double-applies turns one retry into two charges.

## The Result describes the enqueue, never the work

`success(:enqueued)` means it was accepted. There is no caller to tell what happened, which is
why [`every-operation-reports-what-it-did`](every-operation-reports-what-it-did.md) is what
makes this legal at all: the deferred outcome is recorded exactly where a synchronous one is.

**A raise retries; a `failure` does not.** A failure is expected and the operation has already
recorded it, so repeating it would repeat a decision that will not change.

## Everything that goes on the queue must survive the trip

Two things follow, and both are refused at enqueue rather than discovered in the job:

- **The arguments are asserted at enqueue.** The operation is built and thrown away, so
  `call_later` refuses exactly what `call` refuses. Without it a wrong type was accepted,
  answered `success(:enqueued)`, and burned its whole retry budget failing.
- **The actor must be nameable.** Nothing here says an actor is a record — `permits?` needs
  only `may?` — so an actor with no `id` is legitimate and cannot be rebuilt on the other
  side. It used to be dropped in silence: the caller was told the work was accepted, the job
  died, and no audit entry was written at all.

- **Agreed:** Fritz, 2026-08-30 — "implement call_later", after choosing `call_later` over a
  `Schedules` row on the call graph, on the grounds that application code should never name a
  job class.
- **Principle:** `good-boundaries-make-good-neighbours`
- **Guard:** the generated `operation_job.rb` and the three writing operations — architecture.
  The operation asserts, refuses an unnameable actor, and enqueues; the job rebuilds the
  actor and calls the operation. `perform_later` appears nowhere else, so the call graph needs no edge to an
  entry point and the rule that nothing may call one stays absolute. Proven by
  `generated_base_classes_test.rb`, a listed suite guard.
- **Guard:** `Shipshape/OnlyTheDoorIsCalled`, whose `DeferrableKinds` decides which kinds may
  be sent `call_later` at a call site.
- **Guard's limit:** **a failure is dropped, and whether that is right depends on the failure
  being an outcome.** [`an-operation-answers-a-result`](an-operation-answers-a-result.md) says
  a defect raises rather than coming back as a Result, so a transient condition — a gateway
  timeout — is a raise and retries. A `failure(:gateway_unavailable)` written anyway is lost
  here with no retry and no caller to hear it, and nothing catches that: the distinction is a
  judgement about what an outcome is, made per operation.

  `ATTEMPTS` is a count of attempts, not of retries: `ATTEMPTS = 1` runs once and does not
  retry. A `Shape` argument cannot be deferred at all — ActiveJob refuses it, and
  `Shape#to_h` is the caller's answer. Nothing checks that a deferred command is idempotent
  in fact; `Shipshape/CommandsProveIdempotence` checks only that somebody wrote down how.
