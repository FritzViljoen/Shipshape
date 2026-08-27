# `the-call-graph-is-declared` — Every class has a kind, and which kinds may call which is declared

Every class in the covered trees has a **kind**. The kinds that may call each other are
declared once, as a matrix, in one file. A call whose (caller kind, callee kind) pair is
absent from the matrix is an offence, and **no kind may call its own kind** — a rule the
matrix cannot override.

The default kinds, and an application may name its own:

| Kind | May call |
|---|---|
| request handling | workflow, command, query |
| workflow | command, query |
| command | query, entity, record |
| query | entity, record |
| entity | nothing |
| record | nothing |

**Workflow, command and query are all *operations*** — a class with one public method, as
[`one-operation-one-class`](one-operation-one-class.md) requires. The kinds differ in what
they may reach, which is the only thing a kind is for.

**There is no kind for talking to the outside.** A read of somebody else's store is a
query; a write to it is a command. Whose database it is changes nothing about what the
operation is, and REST drew that line already. A kind whose only claim is that the store
belongs to someone else would forbid nothing the existing pair does not — and a kind that
forbids nothing is a name.

**An *entity* is a domain object: a thing the code reasons about, detached from the
database.** A value without identity — a money, a date range — lives in the same tree and
has the same row, so it is not a separate kind. A kind that forbids nothing is a name, not
a kind.

**No kind calls its own kind.** One rule, and it is the whole of what people mean by a
sister call. It lives in the guard rather than in the matrix: a matrix row that names
itself is refused as a contradiction, not honoured as a permission, so no configuration
can allow one.

A sister call is how a class quietly becomes the kind above it. Everything below is a
consequence of that one rule, not a separate rule:

- **A command is one write.** A command that calls a command is sequencing writes, which
  is a workflow's job — so it has become a workflow without saying so, and therefore
  without a workflow's obligations. That is the real cost: nobody made those steps
  idempotent, and nobody checked that stopping between them leaves a legal state.
- **A query is one read.** A query that calls a query is two reads wearing one name, the
  second invisible to whoever asked. It is the shape an N+1 arrives in.
- **A workflow's whole content is its sequence.** Nesting one inside another hides the
  sequence, which was the only thing it had to offer.
- **An entity holds another entity; it does not build one.** Composing is the caller's
  job, and an entity that constructs its neighbours is deriving — which
  [`an-entity-is-composed-not-flattened`](an-entity-is-composed-not-flattened.md) forbids
  for the same reason.

**The rule has a price, and it is worth naming.** A change spanning records can no longer
be one command wrapping a second in a transaction. It becomes a workflow, and a workflow
spans transactions — so each step has to be idempotent and each intermediate state has to
be legal. That is more work, and it is work the transaction was hiding rather than doing.

**This is the load-bearing guard of the canon.** A rule cannot escape its home if there is
nowhere reachable to escape to. It is what stops a call sideways into a sibling area, and a
call upward from a record into an operation, becoming the first instance of a new
convention that nothing yet forbids.

It is also what bounds the second failure of reachability: a rule everything can
reach becomes the place unrelated things are put.

- **Principle:** `good-boundaries-make-good-neighbours`, and it owns this law outright —
  placement and reachability are one subject, which is why that principle carries both.
- **Guard:** `Shipshape/CallGraph`. Resolves the inspected file's kind by path, and a
  called constant's kind by turning its name into the path a loader would expect and
  looking for that file under each kind's roots. Fails a call whose pair is not in the
  matrix, and fails any same-kind call before the matrix is consulted. Refuses a matrix
  row that names itself.
- **Guard's limit:** it resolves receivers syntactically. A call through a local assigned
  earlier, through a method that returns a collaborator, through `send`, or through any
  metaprogrammed dispatch, is invisible. A class it cannot assign a kind to is skipped
  rather than failed — and the count of skipped classes is reported, because a silently
  unclassified tree is exactly the coverage-shaped hole this canon warns about.
