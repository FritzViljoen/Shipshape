# `co-change-is-a-fact-not-a-verdict` — Files that land in one commit are evidence, not a merge order

How often two files change in the same commit is true whatever either one imports. A call
graph states what the code says today; co-change states what actually moved together,
regardless of what the code says. Neither substitutes for the other — a refactor that cuts a
declared edge while co-change stays flat has moved code without decoupling anything, and only
having both catches that.

**A high shared-commit count is not a verdict that two files belong in one class, module, or
team.** It is a count. What it means is for the reader to decide, the same discipline
`shipshape tables` holds for a nullable column. The same walk also counts each file's own
total commits — churn — and that is reported beside the pairs for the same reason: a busy
file is a fact, not a verdict that it is the wrong shape.

**It is safe to run from wherever the reader is standing, including a linked worktree.** It
never looks for a `.git` directory itself; every call passes the given root straight to git as
`-C root` and lets git resolve `git-common-dir` on its own. That distinction is not academic —
a tool that walks up hunting a `.git` directory treats a linked worktree's `.git` *file* as
"not here" and keeps climbing until it reaches the main checkout, then reports every file's
churn as zero with no error. Verified against this gem's own two checkouts: the same commit
read from the linked worktree and from its main checkout returns byte-identical pairs and
churn.

- **Principle:** `nothing-is-hidden`
- **Guard:** not built yet — `shipshape cochange` gathers the count and stops; no cop turns
  it into a threshold, the same position `shipshape tables` holds against
  `AbsenceIsAbsenceNeverAValue`.

- **Guard's limit:** it reads commits, not intent, and four things follow from that.

  A file with no history — created this run, or one every commit it appeared in was too
  large to pair — reports zero shared commits with everything, indistinguishable from a file
  that is genuinely uncoupled from the rest of the tree.

  A repository with few commits makes the ratio noisy: two files that happened to change
  together twice out of three commits each read as tightly bound, and the sample is nothing.
  The ratio is a fraction of a small number before it is a fraction of anything real.

  The commit cap trades one blind spot for another on purpose. A commit touching more files
  than the cap contributes to each file's own total but forms no pair at all — chosen at 50,
  clear of a real multi-file slice but well under the hundreds a schema regeneration or a
  `rubocop -a` sweep touches at once. A genuine refactor that happens to cross the cap in one
  commit is invisible to every pair it would have formed; splitting it into smaller commits is
  the only way back into view. Lower the cap and more mechanical noise counts as coupling;
  raise it and a real sweep starts defining every pair in the repository.

  Rename handling resolves a chain of `git mv`-clean renames to the name at HEAD, however many
  times a file moved on the way there — verified against a real three-hop rename in this
  gem's own host. What it cannot do: a rename below git's similarity threshold — a move
  alongside a heavy rewrite — reports as an unrelated delete and add, and the file's earlier
  history stays orphaned under the old name exactly when it moved the most. A copy is not
  attributed at all; the two files it produced are counted apart, correctly, since the
  original keeps its own life. And a merge commit's diff is not read by default, so a change
  introduced only while resolving a conflict — present on neither parent — is invisible here.
