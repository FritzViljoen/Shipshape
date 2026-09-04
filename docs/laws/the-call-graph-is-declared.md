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
- **A query owns its read entirely**: it reads every table it needs
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

  **A name listed under `BaseClasses` resolves to its kind without a file.** Resolution
  otherwise goes through the filesystem, so a constant belonging to a gem resolves to
  nothing and is skipped — and `ActiveRecord::Base` is exactly that. The one constant in a
  Rails application that names persistence outright was the one this could not see, so
  `ActiveRecord::Base.connection.execute` reached the database from a shape, and
  `ActiveRecord::Base.transaction` opened one from a controller, with nothing objecting.

  **A class naming the base class it inherits from is exempt**, because a parent is not a
  sister. Without that, a record naming `ApplicationRecord` was refused as a record calling
  a record — an offence whose message was not true of the code it pointed at, which
  `enforcement-messages-are-documentation` makes a defect in itself.
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

- **Guard:** `shipshape check`'s coupling ratchet — `Shipshape::Coupling`,
  `Shipshape::CouplingDelta`. Edges come from `Shipshape/CallGraph`'s own offences, read back
  over the `RECORD_COUPLING_ENV` channel `BaseTestClassLines` already uses. **"Governed" does
  not** — it comes from `Shipshape::Kinds` directly, the same resolver a callee's kind already
  goes through, walked over the filesystem rather than asked which files RuboCop happened to
  inspect. Those two used to be different derivations that disagreed: a file a `Kinds` glob
  claims but `AllCops`, or the cop itself, excludes — or an `Include` misses, or that is blank
  enough for RuboCop to skip its own investigation of it — matched a callee's name fine while
  never once appearing "governed," so it sat outside the stable bucket forever, in both trees,
  on every run. One resolver closes that: a file `Kinds` would classify is governed whether or
  not RuboCop was ever pointed at it.

  **One resolver is not one base dir.** A nested `.rubocop.yml` shifts `Shipshape/CallGraph`'s
  own `base_dir_for_path_parameters` for the subtree beneath it — `test/canaries/.rubocop.yml`,
  in this gem's own repo, is exactly that shape, inheriting the root `Kinds` but resolving its
  globs against `test/canaries/` instead. Governance and a callee's own path both used to be
  computed against whichever base dir happened to apply to the file being asked about, while
  a caller's own path always comes back from RuboCop relative to the run's own root. A callee
  under a shifted subtree therefore never matched anything, in either tree, on every run — the
  same failure the paragraph above closes, surviving one level down. Both are now resolved
  against the config that actually governs the file in question, then reported relative to the
  run's own root throughout, the one frame RuboCop's own paths already use. An explicit
  `--config` pins one file for the whole run by RuboCop's own design, so it flattens this the
  same way it flattens RuboCop's own resolution — nesting only diverges from the top level
  when nothing pins it.

  The number is a call graph, not a count: every edge `Shipshape/CallGraph` resolves, legal or
  not, is split three ways between the merge base and HEAD, **after both sides' paths are
  canonicalised through git's own rename detection** (`Shipshape::RenamedPaths`, reading
  `git log --name-status -M`) onto their name at HEAD. **Among files governed at both trees**
  — the same name, governed both times, moves notwithstanding — is what fails the build if it
  rises; a genuinely new call on an already-governed file has nowhere to hide inside it, and
  neither does one riding along with a file that moved in the same commit. **Arriving with a
  newly governed file** and **leaving with a file that lost governance or was deleted** are
  reported beside it and never fail: bringing code under governance, or losing it, is not a
  call anybody added or cut, and a ratchet that billed a detangling slice for the coupling
  already sitting in the file it moved would make detangling the expensive path. A delete paired
  with an unrelated add is not a move — git's own content-based rename detection is what decides
  that, the same test a human reviewing the diff would apply — so it is disclosed as one
  departure and one arrival, honestly, rather than guessed at.

  An edge resolved through `BaseClasses` has no file only when the base class itself resolves
  to none — a gem constant such as `ActiveRecord::Base`, or a name matching no file under any
  glob — and only then is it stable by construction on both sides, because there is no path for
  either tree to disagree about. **A declared base class that also has a file inside a governed
  glob is not that case.** `Command` declared at `app/commands/command.rb` resolves to that
  path exactly like any other callee: it is governed, it can arrive or leave, and every edge
  naming it moves with it — canonicalised the same as any other rename, `application_record.rb`
  included, rather than exempted from the count that governs everything else reaching it.
- **Guard's limit:** canonicalisation is only as good as git's own rename detection, which
  reasons about content similarity, not identity — a move heavy enough with edits that git
  itself would show it as a delete and an add is invisible to `RenamedPaths` exactly as it
  would be to a person reading the diff, and that file's edges fall back to the pre-canonical
  behaviour: one leaving with the old path, one arriving with the new one. The same is true of
  a shallow clone whose history does not reach back to where the rename happened. **A path
  vacated by a rename and later reused for a different file** is also outside what path-based
  identity can tell apart — `RenamedPaths` would alias the new file to the old one's name — a
  pre-existing limit of resolving identity by path at all, not one this fix introduces or
  closes. The arriving and leaving counts are informational only and never fail the build, on
  purpose — which also means there is no ceiling on how much coupling a newly governed file may
  carry in on its first day; the ratchet cannot object to any of it, by design, so a large
  legacy file walked into governance still needs a human to have looked at what it brought. And
  a repository whose config declares no `Kinds` at all — or none this cop's own `Enabled`
  reaches — governs no files in either tree, so every edge is invisible to it and the number
  reads `0 -> 0` on every run: `flat` looks identical to "measuring nothing" and this guard
  cannot tell the two apart. It inherits every blind spot the guard above states for
  `Shipshape/CallGraph` itself — a receiver resolved through a local, a method call, `send`,
  or any dispatch this cop does not resolve syntactically forms no edge here either, coupled
  or not.
- **Guard:** `Shipshape::ConfigAt`, read by `Coupling#config_at` and by `Check#population` for
  the base tree. The base tree in a `check` comparison is by definition older than the process
  reading it, so its config can legitimately name a cop this version renamed or removed —
  RuboCop's own loader raises `RuboCop::ValidationError` on that unconditionally. `ConfigAt`
  asks it to warn instead, through `RuboCop::ConfigLoader.ignore_unrecognized_cops` (the same
  switch `--ignore-unrecognized-cops` sets for the CLI, so `Offences`, `Guards` and
  `BaseTestClassLines` use it too for their own subprocess reads of the base tree), and turns
  the warning back into the cop names it named. `check` reports every one it had to skip.
  Nothing else RuboCop's loader can raise — malformed YAML, an unresolved `inherit_from`, any
  other validation — goes through this switch, so those still fail the run exactly as before.
- **Guard's limit:** the base tree is read with the current version's registry, so a cop the
  base names and this version lacks is skipped, and the base's governed set is measured
  without it. A skip is not silent — `check` names every cop it skipped — but it is also not a
  measurement: a kind that cop alone would have scoped, or an offence count only it produced,
  reads as absent rather than as unknown, for exactly as long as the base tree still needs
  that name. The window closes on its own once a repository's own merge-base moves past the
  rename, and nothing here shortens it.
