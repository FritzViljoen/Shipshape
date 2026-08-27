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
| legacy_query | entity, record |
| legacy_command | entity, record |
| entity | nothing |
| record | nothing |

**The two legacy kinds are the doors to the old world, and the only classes permitted to
speak to it.** A governed class never reaches legacy code directly; it goes through a door,
and the `*_legacy.rb` suffix means that dependency is visible at the call site without
opening anything.

There are two rather than one so the return shape survives the crossing: a legacy query
answers with entities, a legacy command answers with a Result. A single door would have to
answer both ways, and a flag deciding which is the shape this canon refuses.

**They share one suffix, and the base class tells them apart.** The path says "this is a
door"; inheritance carries the return shape, so putting that fact in the filename too would
be a second copy of it — and the copy is the one that goes stale.

**Their population is the migration backlog made countable**, and the ratchet turns it into
a number that only falls. A door's own calls into the old world are invisible to the guard,
because unclassified constants are skipped — which is exactly what a door is for.

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

**Two kinds carry a filename suffix — `*_controller.rb` and `*_record.rb` — and it is the
same reason both times: they are the two that are infrastructure rather than domain.**
Everything the MVC model used to hold has been split into workflows, commands, queries and
entities. What is still called a record is only the table, and the suffix says so out loud,
so that nobody mistakes it for the thing it used to be. A class named `Person` that is
really a table is the beginning of the god object;
[`persistence-holds-no-behaviour`](persistence-holds-no-behaviour.md) is easier to hold when
the file name already admits what it is.

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

**A class naming itself is not a sister call.** `Result.success(...)` written inside
`Result` is one entity, not two talking, and the guard resolves the constant to a file to
tell the difference.

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
- **Kind resolution:** the superclass decides; the path only decides whether a file is
  governed at all. `Shipshape/CallGraph` reads `BaseClasses` for the mapping. A governed
  file naming no declared base class falls back to its path.
- **Layout:** a kind is a list of globs, so a conventional `app/` tree and a Packwerk
  `packs/*/` tree are the same mechanism — the glob's trailing wildcards are dropped
  and what remains is expanded on disk, giving one autoload root per pack. Two packs may
  hold the same constant name; each resolves inside its own pack.
- **Guard's limit:** it resolves receivers syntactically. A call through a local assigned
  earlier, through a method that returns a collaborator, through `send`, or through any
  metaprogrammed dispatch, is invisible. A class it cannot assign a kind to is skipped
  rather than failed — and the count of skipped classes is reported, because a silently
  unclassified tree is exactly the coverage-shaped hole this canon warns about.

  Root expansion reads the disk once per glob and caches it, so a directory created
  mid-run is not seen. It also resolves a constant by **name to path**, which means an
  application whose constant does not follow its loader's naming — an acronym, an
  explicit `inflect` rule — resolves to no file and is skipped. Skipped, again, not
  failed.

  **The superclass is read, not parsed** — a regular expression over the file's source,
  matching the first `class X < Y`. A superclass written as an expression, assigned through
  a constant, or produced by a class-generating call is invisible, and the file falls back
  to its path. `one-level-of-inheritance` is what keeps that rare.

  **The suffixes cut a hole of the same shape.** A file in the records tree not named
  `*_record.rb` matches no kind, so it is skipped rather than failed — the file has quietly
  left coverage. That is why the count of unclassified files is reported rather than
  assumed to be zero.
