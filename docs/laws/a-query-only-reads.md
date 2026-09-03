# `a-query-only-reads` — A query is one read, and the call graph cannot tell you otherwise

A query reaches a record, shapes what it found, and answers. It never writes. A write is a
command, with its own name, its own permission and its own transaction.

**The call graph allows the call and cannot see the message.** A query reaching a record is
exactly what a query is for, so `record` is in the query's matrix row and always will be.
What the matrix governs is *which kinds talk*; what it cannot govern is *what they say*. A
query calling `PersonRecord.create!` is a permitted call carrying a forbidden message, and
that is the one gap the matrix leaves open by design.

**A query opens no transaction, because a read needs none.** The generated `Query`
deliberately has none — a transaction wrapped around a read holds a connection for nothing.
So a write from inside a query runs outside any transaction this canon knows about. A caller
sequencing two queries has no rollback for the second, and every name on the path says nothing
happened. That is the whole cost: not untidiness, but a write nobody can undo and nobody can
find.

**It is also how a query stops being one.** The name says read, the call site reads as a read,
and the caller has no reason to think about ordering, retries or idempotence. A command
announces all three by being a command.

## What a query answers, and how a caller asks

**Three answers, and no envelope: `nil`, a shape, or an array of shapes.** Finding nothing is
an answer rather than a failure, so a lookup that found no row says `nil` and a list that
matched no rows says `[]`. A `Result` here would make every caller unwrap a value that was
never in doubt. A refusal still raises.

`nil` was refused at first, and the base class was wrong rather than the law: the commonest
read in any application — find one row by code — had no legal answer, and the workaround was
to wrap it in a one-element array, which is a shape of answer nobody wanted.

**The caller asks `.present?`, of the call itself.**

```ruby
if FindInvitation.call(code: text_param!(:code)).present?
```

That one predicate is correct across all three answers — `nil` and `[]` are absent, a shape
and an array of shapes are present — so "did it find anything" has one spelling whether the
query answers one or many. Asking a **local** instead is refused: nothing at the condition then
says which operation answered or what it answered, and the reader has to trace the local back
before they can tell an outcome from a rule. That is
[`no-decisions-in-request-handling`](no-decisions-in-request-handling.md)'s half of this.

- **Principle:** `good-boundaries-make-good-neighbours`
- **Guard:** `Shipshape/PresenceIsNotRedefined`, over the shape tree. Fails `present?`, `blank?`
  or `empty?` defined on a shape — `blank?` consults `empty?`, so banning one name leaves the
  answer decidable two names over. It keeps `.present?` meaning one thing at the call site:
  whether the query found anything. The other half is
  [`no-decisions-in-request-handling`](no-decisions-in-request-handling.md), which is what makes
  `.present?` the only question an action may ask of an answer.
- **Guard:** `Shipshape/QueriesOnlyRead`, over `query`, `io_query` and `legacy_query`. Fails a
  known writing message — `create!`, `update!`, `save`, `destroy_all`, `update_all`,
  `insert_all` and the rest — sent to a chain rooted in a constant that resolves to a record.
- **Guard's limit:** the write must be rooted in a **record constant this configuration
  resolves**. `PersonRecord.create!` and `PersonRecord.find(1).update!` are seen; a write
  through a local, an ivar, or an object handed back by something else is not — there is no
  constant, and nothing states what the receiver holds. It reads method names from a closed
  list, so a writer the list does not know is invisible, and a same-named method on something
  that is not a record is a false positive to be argued in review.

  It says nothing about a write reached through a called method, and nothing about raw SQL.
  **And it does not check the other direction:** a command that only reads is not reported,
  because "this class performs no write" is a claim about absence that no read of the source
  can make — the write may be one call away. That a read-only command should have been a query
  stays a judgement.
