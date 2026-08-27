# `the-call-graph-is-declared` — Every class has a kind, and which kinds may call which is declared

Every class in the covered trees has a **kind**. The kinds that may call each other are
declared once, as a matrix, in one file. A call whose (caller kind, callee kind) pair is
absent from the matrix is an offence.

The default kinds, and an application may name its own:

| Kind | May call |
|---|---|
| request handling | workflow, command, query |
| workflow | command, query, gateway |
| command | query, gateway, entity, record |
| query | entity, record |
| gateway | entity |
| entity | entity |
| record | nothing |

**Workflow, command, query and gateway are all *operations*** — a class with one public
method, as [`one-operation-one-class`](one-operation-one-class.md) requires. The kinds
differ in what they may reach, which is the only thing a kind is for.

**An *entity* is a domain object: a thing the code reasons about, detached from the
database.** A value without identity — a money, a date range — lives in the same tree and
has the same row, so it is not a separate kind. A kind that forbids nothing is a name, not
a kind.

**A query may not call a query.** A query is *one* read. A query that calls a query is two
reads wearing one name, the second invisible to the caller, and that is the shape an N+1
arrives in. Where a caller needs two reads it asks for two, and the composition is visible
at the place that wanted it.

**A command may not call a command.** A command is *one* write. Sequencing writes is the
workflow's job, and a command that calls a command has become a workflow without saying so
— with none of a workflow's obligations, which is the actual cost: nobody made those steps
idempotent, and nobody checked that stopping between them leaves a legal state.

**This is the row with a price, and it is worth naming.** A change spanning records can no
longer be one command wrapping a second in a transaction. It becomes a workflow, and a
workflow spans transactions — so each step has to be idempotent and each intermediate state
has to be legal. That is more work, and it is work the transaction was hiding rather than
doing.

**A workflow does not call a workflow.** A workflow's whole content is its sequence;
nesting one inside another hides the sequence, which is the only thing it had to offer.

**A gateway is a command that crosses the process boundary**, and it is the only kind
permitted to talk to anything outside. It reaches no record and no query, so the external
call and the write that records its result are two visible steps rather than one — which
is what makes the pair retryable, and what stops a failed remote call leaving a half-written
row behind.

**Request handling cannot reach a gateway directly.** An external call has a domain
meaning — a payment taken, a booking confirmed — and that meaning lives in the command or
workflow that wanted it, not in an action.

**This is the load-bearing guard of the canon.** A rule cannot escape its home if there is
nowhere reachable to escape to. It is what stops a call sideways into a sibling area, and a
call upward from a record into an operation, becoming the first instance of a new
convention that nothing yet forbids.

It is also what bounds the second failure of reachability: a rule everything can
reach becomes the place unrelated things are put.

- **Principle:** `good-boundaries-make-good-neighbours`, and it owns this law outright —
  placement and reachability are one subject, which is why that principle carries both.
- **Guard:** `Shipshape/CallGraph`. Resolves a class's kind by base class first, then by
  path. Fails a call to a constant whose kind is not reachable from the calling file's
  kind. The matrix is data, in one file, and the cop reads it.
- **Guard's limit:** it resolves receivers syntactically. A call through a local assigned
  earlier, through a method that returns a collaborator, through `send`, or through any
  metaprogrammed dispatch, is invisible. A class it cannot assign a kind to is skipped
  rather than failed — and the count of skipped classes is reported, because a silently
  unclassified tree is exactly the coverage-shaped hole this canon warns about.
