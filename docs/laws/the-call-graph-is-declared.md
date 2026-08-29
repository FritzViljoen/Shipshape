# `the-call-graph-is-declared` — Every class has a kind, and which kinds may call which is declared

Every class in the covered trees has a **kind**. The kinds that may call each other are
declared once, as a matrix, in one file. A call whose (caller kind, callee kind) pair is
absent from the matrix is an offence, and **no kind may call its own kind** — a rule the
matrix cannot override.

The default kinds, and an application may name its own:

| Kind | May call |
|---|---|
| request handling | workflow, command, query, io_command, io_query, legacy_command, legacy_query |
| workflow | command, query, io_command, io_query, legacy_command, legacy_query, shape |
| command | query, legacy_query, shape, record |
| query | shape, record |
| io_command | io_query, shape |
| io_query | shape |
| legacy_command | query, legacy_query, shape, record |
| legacy_query | shape, record |
| shape | nothing |
| record | nothing |

**The `io_` pair reads and changes state outside this process**, and the prefix means the
crossing is visible at every call site. They are **sisters** of the internal pair — an
`io_command` is a command whose store belongs to somebody else — so a command may not call
one.

**The reason is the transaction, and it is the only one that matters.** A command is exactly
one transaction. An external call inside one holds a database transaction open across a
network round trip, which is how a slow third party takes a database down, and the remote
write cannot be rolled back by it in any case. **A read is no better:** it holds the
transaction open just as long. So neither a command nor a query does IO — the external call
and the local write that records its result are two steps, sequenced by a workflow, which is
the only kind that has accepted the bill for spanning them.

**An `io_command` touches no record**, for the same reason: a failed remote call then leaves
no half-written row behind, and the pair is retryable. Assume retries — a workflow's only
recovery is to run the sequence again.

**And it reads in its own world, not in ours.** `io_command → io_query` mirrors
`command → query` — a write may read first, and fetching a token before posting is that
shape. What it may not do is reach a `query`: an external write pulling from the local store
is reaching back across the boundary it just crossed, and anything it needs from here should
have been handed to it like every other input.

**The two legacy kinds are the doors to the old world, and the only classes permitted to
speak to it.** A governed class never reaches legacy code directly; it goes through a door,
and the `*_legacy.rb` suffix means that dependency is visible at the call site without
opening anything.

There are two rather than one so the return shape survives the crossing: a legacy query
answers with shapes, a legacy command answers with a Result. A single door would have to
answer both ways, and a flag deciding which is the shape this canon refuses.

**A door mirrors the row of the kind it is a sister to, because it *is* that kind** — it
only happens to wrap something old. A command may read through the reading door exactly as
it reads through a query, and may not call the writing door at all, exactly as it may not
call a command.

**They share one suffix, and the base class tells them apart.** The path says "this is a
door"; inheritance carries the return shape, so putting that fact in the filename too would
be a second copy of it — and the copy is the one that goes stale.

**Why they are marked, rather than just wrapped:** the new shape only admits its own kinds.
A workflow may sequence commands and queries and nothing else, so an unwrapped legacy
service cannot be called from one at all — the graph has no row for it. Wrapping is how old
code gets in, and the mark is what keeps the crossing visible at the call site instead of
dissolving into the new code as though it had always belonged.

**Their population is the migration backlog, and it does not only fall.** It rises while the
old world is being pulled into the new shape, one door at a time, and falls only as each
wrapped thing is rewritten and its door deleted. That is a curve, not a ratchet — the
ratchet governs violations, and a door is not a violation. What the mark buys is that the
number is knowable at all.

**And there is no legacy kind for anything else — no legacy controller, no legacy shape.**
The line is this: **a kind is for a shape you intend to keep; the ratchet is for a shape you
intend to remove.**

A door earns a kind because the old world still exists and has to be reachable from the new
one; it is a legitimate, useful shape with a job. A legacy controller wraps nothing — it *is*
the thing to be rewritten — so giving it a kind would bless it, make it legal, and leave
nothing counting it down.

On a real application that means every existing controller is `request_handling` and most of
them violate the matrix on day one. That is correct and survivable: the baseline is taken
from the merge-base, only new violations fail, and **the count is the migration progress**.
Unlike a register of which controllers are "done", it cannot rot — a controller is migrated
exactly when it stops violating, and nobody maintains a list.

A door's own calls into the old world are invisible to the guard,
because unclassified constants are skipped — which is exactly what a door is for.

**Workflow, command and query are all *operations*** — a class with one public method, as
[`one-operation-one-class`](one-operation-one-class.md) requires. The kinds differ in what
they may reach, which is the only thing a kind is for.

**An *shape* is a domain object: a thing the code reasons about, detached from the
database.** A value without identity — a money, a date range — lives in the same tree and
has the same row, so it is not a separate kind. A kind that forbids nothing is a name, not
a kind.

**Two kinds carry a filename suffix — `*_controller.rb` and `*_record.rb` — and it is the
same reason both times: they are the two that are infrastructure rather than domain.**
Everything the MVC model used to hold has been split into workflows, commands, queries and
shapes. What is still called a record is only the table, and the suffix says so out loud,
so that nobody mistakes it for the thing it used to be. A class named `Person` that is
really a table is the beginning of the god object;
[`persistence-holds-no-behaviour`](persistence-holds-no-behaviour.md) is easier to hold when
the file name already admits what it is.

**No kind calls a sister, and every kind is its own sister.** One rule, and it is the whole
of what people mean by a sister call. It lives in the guard rather than in the matrix: a
matrix row naming a sister is refused as a contradiction, not honoured as a permission, so
no configuration can allow one. `Sisters` declares the groups — a legacy command is a
command that wraps something old, so the two are one kind for this purpose.

A sister call is how a class quietly becomes the kind above it. Everything below is a
consequence of that one rule, not a separate rule:

- **A command is exactly one transaction. A workflow is several.** That is the sharpest
  form of the rule and the reason for it. A command that calls a command has either nested
  a transaction or silently widened one, and nobody decided which — whereas a workflow
  crossing transactions is *obliged* to make each step idempotent and each intermediate
  state legal. Sequencing writes is the workflow's job because a workflow is the thing that
  has accepted that bill.
- **A query is one read**, and it owns that read entirely: it reads every table it needs
  and builds every part it returns. A query that calls a query is two reads wearing one
  name, the second invisible to whoever asked, and it is the shape an N+1 arrives in —
  whether the second read fetches a list or fetches one customer.

  **Where two queries want the same sub-shape, that is the signal it is not a part but a
  peer.** Promote it, give it its own query, and let whoever wanted both do the combining —
  a workflow or a command may call two queries, and deciding to combine two reads is a
  decision, which belongs with a caller rather than inside a read.
- **A workflow's whole content is its sequence.** Nesting one inside another hides the
  sequence, which was the only thing it had to offer.
- **A shape holds another shape; it does not build one.** Composing is the caller's
  job, and a shape that constructs its neighbours is deriving — which
  [`a-shape-is-composed-not-flattened`](a-shape-is-composed-not-flattened.md) forbids
  for the same reason.

**A class naming itself is not a sister call.** `Result.success(...)` written inside
`Result` is one shape, not two talking, and the guard resolves the constant to a file to
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

  **A glob may name one file rather than a tree** — `app/models/contest.rb` — which is how
  an application says two kinds share a directory before it has moved anything. Such a glob
  matches only the constant whose own path it is; it is not a root, because resolving
  against its directory would classify every neighbour the same way.

  **The superclass is read, not parsed** — a regular expression over the file's source,
  matching the first `class X < Y`. A superclass written as an expression, assigned through
  a constant, or produced by a class-generating call is invisible, and the file falls back
  to its path. `one-level-of-inheritance` is what keeps that rare.

  **The suffixes cut a hole of the same shape.** A file in the records tree not named
  `*_record.rb` matches no kind, so it is skipped rather than failed — the file has quietly
  left coverage. That is why the count of unclassified files is reported rather than
  assumed to be zero.
