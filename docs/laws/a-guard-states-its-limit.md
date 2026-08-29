# `a-guard-states-its-limit` — Every law says what its guard does not cover, and every guard is tested by removal

Two obligations, and they are the ones that make the rest of this list worth reading.

**Every law states its guard's blind spot.** A guard that does not say what it misses is
read as covering everything, so a green build comes to mean more than it earned. Naming the
gap costs a paragraph; discovering it costs an incident.

**Every guard has a test proven to fail.** Delete the guard, watch the test go red, restore
it. A guard nobody has watched fail is coverage-shaped and may enforce nothing at all —
enabled against an empty file list, scoped to a tree that no longer exists, or matching a
construct the codebase stopped using.

**A law with no guard says so, and is called a convention.** Calling it a law does not make
it hold. Several laws here are part-guarded and say which half the build actually holds;
[`no-decisions-in-request-handling`](no-decisions-in-request-handling.md) is the clearest.

**A checked-in baseline of existing violations is forbidden.** It has a regenerate button,
and pressing it on a red build is exactly what erases the signal. The baseline is derived
from version control on every run.

- **Principle:** `nothing-fails-quietly` governs. `make-the-wrong-thing-impossible` produces
  the tested-by-removal half.
- **Guard:** `CanonTest`, in this gem's own suite — see
  [`one-mechanism-guards-everything`](one-mechanism-guards-everything.md), which explains why
  this one check is not itself a cop. Fails when a law file
  has no guard section or no limit section, when it names a cop that does not exist, or when
  a cop exists that no law names. Each cop's own removal test is the second half, and the
  suite fails if a cop has no such test.

- **Guard's limit:** it checks that the limit section and the removal note **exist**, never
  that what either says is true, complete, or current. Nobody re-runs the removals, so a
  note describing a mutation that no longer reddens anything passes. A stale blind-spot paragraph passes. That judgement is the
  author's and no check will ever make it — which is the honest reason this law is written
  down rather than assumed.
