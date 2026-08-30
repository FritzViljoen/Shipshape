# `io-is-its-own-kind` — A call to the outside is an operation of its own, never a line inside another

Talking to anything across a network is what `io_command` and `io_query` are for. A command,
a query, a workflow, a shape, a component, a record and a controller do not do it.

**The reason is the transaction, and it is the same reason a command may not call a command.**
A command is exactly one transaction, opened by the base class before `call` runs. An HTTP
request inside one holds a database connection open across a network round trip — for the
far end's latency, its timeout, and every retry underneath. Under load that is how a
connection pool empties while every individual query looks fast.

**A query is the worse case, not the better one.** It has no transaction to blame, so nothing
about it looks dangerous: a read is the thing nobody reviews twice. The slow call hides
behind a name that promises the opposite.

**Splitting them is what makes the failure expressible.** The outside call and the local write
that records it are two steps, and a workflow is the only kind obliged to make each step
idempotent and each intermediate state legal. Written as one command they are one step that
can half-happen — the charge went through, the row did not — and no name in the codebase says
so.

**The call matrix cannot hold this, which is why the law needs its own guard.** The matrix
refuses `command → io_command`, and that works only for IO an application has already filed
as a kind. `Net::HTTP` belongs to a gem, resolves to no file under any declared glob, and is
skipped. So the rule held for the disciplined case and not for the form IO actually arrives
in — a line in the middle of a method.

- **Agreed:** Fritz, 2026-08-30 — "please add the gaurds and documents", after the inline-IO gap was reported and left open for a decision.
- **Principle:** `good-boundaries-make-good-neighbours`
- **Guard:** `Shipshape/IoIsItsOwnKind`, over every kind except `io_command`, `io_query` and
  the legacy doors. Fails any message sent to a constant on its `Constants` list — the
  standard library's networking and the HTTP clients a Rails application is likeliest to
  have. **The list is the fact rather than a description of one:** being named on it is what
  makes a constant IO, nothing infers it, and an application adds its own vendors.
- **Guard's limit:** it knows the clients it is told about and no others. Every vendor SDK —
  `Stripe`, `Twilio`, an S3 client — is invisible until someone adds it, and so is any wrapper
  an application wrote around one. IO reached through a local or handed in as a collaborator
  is invisible too: there is no constant to read.

  **The filesystem is deliberately absent from the defaults.** `File.join` is a string
  operation and `File.read` is not, and telling them apart needs a per-constant method list
  that would drift from the day it was written. An application that wants `File` and `Dir`
  governed adds them and accepts the noise. Named here so the omission is a decision rather
  than an oversight somebody finds later.
