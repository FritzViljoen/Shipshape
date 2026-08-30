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

- **Agreed:** Fritz, 2026-08-30 — "definitely", ratified on review. Drafted by an agent in
  answer to "is all our class kinds gaurded", which was a question: a cop and a law were built
  where a finding had been asked for. It found 376 instances across seven public repositories,
  including a class named `...Query` calling `create!`.
- **Principle:** `good-boundaries-make-good-neighbours`
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
