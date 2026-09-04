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
- **Guard:** `CanariesTest`, also in this gem's suite. **A test and a canary answer different
  questions, and a cop needs both.** A removal test asks whether the test exercises the cop;
  a canary asks whether the cop can still fire under a real configuration — the failure where
  a kind's globs stop matching where the code lives, and every cop scoped to that kind goes
  quiet while passing every test it has. So the suite fails when a registered cop has no
  planted canary, when a planted canary does not fire, and when the checked-in canary
  configuration is not what the planter writes.

  **Every registered cop, not every enabled one.** Filtering on the configuration meant a cop
  shipped `Enabled: false` needed no canary while the canon still demanded a law and a test
  for it — fully covered on paper, unprovable in fact. The planted tree turns every cop on for
  its own run, so a cop that is off by default is still shown firing.

- **Guard:** `GuardNamesRealCodeTest`, `CountClaimsMatchCodeTest` and
  `PermittedPredicatesAgreeTest`, also in this gem's suite. Existence is not truth: these
  three each hold one mechanisable slice of whether a Guard paragraph's *claim* still matches
  its cop — a backticked `SCREAMING_SNAKE_CASE` constant that the cop's own source must still
  contain, a spoken-out-loud count next to a real countable set (`AUDITED_DOORS`, a
  `Kinds:` list) that must still match it, and two cops' predicate lists that must still
  agree. See each file's own header for what it catches and why.

- **Guard's limit:** it checks that the limit section and the removal note **exist**, never
  that what either says is true, complete, or current. Nobody re-runs the removals, so a
  note describing a mutation that no longer reddens anything passes. A stale blind-spot paragraph passes. That judgement is the
  author's and no check will ever make it — which is the honest reason this law is written
  down rather than assumed.

  **The three new guards above are a slice, not the class.** Each is anchored on a literal,
  narrow signal — a constant's spelling, a number word beside one named set, one exact anchor
  phrase — chosen because it needs no exemption list. What is left is everything that slips
  between those anchors: a claim spelled a third way, a count about a set nobody gave a name
  a script can find, a paraphrase that is simply wrong without repeating or contradicting any
  fact a script can check. Reading a Guard paragraph against its cop and judging whether the
  prose is still *true* — not just still spelled the same — has no substitute here. It is a
  reader's job, every time a cop changes.

  The canary half has its own blind spot: it proves a cop **can** fire on one planted
  violation, never that it fires on everything it should. A cop narrowed to catch only the
  exact shape of its own canary would pass here and protect nothing else.

  Neither half is independent evidence for the other. A canary and a cop's own test file
  are written by whoever wrote the cop, from the same understanding, so agreement between
  them proves nothing further. `Shipshape/NoTestMixins` reported zero offences against
  `test/support/signs_in_as_admin.rb` — the case the law exists for — while its canary
  fired clean: the canary used `extend self`, which reaches the offence without touching
  constant resolution, and the cop's own test file put every positive case inside the one
  directory the resolver searched. What catches a cop narrowed to its own shape is a case
  built from the law, not from the cop.
