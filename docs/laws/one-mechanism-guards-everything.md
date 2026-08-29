# `one-mechanism-guards-everything` — One gate, one kind of guard, one place to look

Everything this canon enforces is a RuboCop cop, and the only thing that fails a build is
`shipshape check`. Not a rake task. Not a git hook. Not a shell script under `bin/`. Not a
grep in CI. Not a test that reads the source tree.

**The question a codebase has to be able to answer is "what does this enforce?", and the
answer must be one list.** With one mechanism it is: the cop registry, which is derived and
cannot go stale. With five mechanisms there is no list at all — there is a folder of scripts,
a CI file, a hooks config and an oral tradition, and nobody can tell you what is enforced
without reading all of them. That is not a documentation problem. It is why rules get
enforced twice with different edges, and why a rule everyone believes is held turns out to
be held by nothing.

**A second mechanism has no ratchet.** `shipshape check` counts offences against a baseline
derived from the merge base, so a rule can be turned on over a codebase that violates it and
the count only falls. A script bolted on beside it has no baseline, so it has exactly two
settings — advisory, which means ignored, or hard, which means it cannot be turned on at all
in the codebase that needs it most.

**One mechanism means one suppression, and suppression must be greppable.** A cop is silenced
by `# rubocop:disable Shipshape/X`, in the file, next to the code, in a form that greps and
shows up in review. Every other mechanism invents its own escape hatch — an env var, an
exclusion file, a skipped hook — and those are invisible from the code they excuse.

**A guard is not a report.** `shipshape report` and `shipshape coverage` describe the
codebase and fail nothing; `shipshape check` fails and describes nothing new. `shipshape
canaries` fails, and holds this law rather than adding a rule to it. A measure in the
report is not enforcement and never claims to be — which is why a rule is not finished when
the report can see it, only when a cop holds it.

**A law that names a cop nobody built says so.** The Guard line carries the words
**not built yet**, and the law is a convention until the cop exists. Writing the law first is
right; letting the reader believe it is enforced is not.

**A check that verifies the mechanism is not a second mechanism.** `shipshape canaries`
fails a build, and it is allowed for one reason: it enforces no rule. It plants a known
violation per cop and asserts each one fires, so it holds *this law* — that the cop list is
the whole enforcement surface — rather than adding to it. A guard that does not run reports
the same thing as a guard that finds nothing, and nothing else here can tell those apart:
`shipshape check` reads a count, and a count of zero is exactly what a silent cop produces.

It earns none of the exemptions a real gate would need. It has no ratchet because it is
binary by nature: every cop fires, or the surface has a hole. Its escape hatch is not an
exclusion an application writes but the canary tree itself, which is checked in and
greppable. **`shipshape coverage` and `shipshape report` fail nothing** — they describe, and
they exit 0.

**The one exception is this gem's own bookkeeping, and it is bounded.** The check that holds
the law-to-cop wiring is a test in shipshape's suite, not a cop — a cop parses Ruby, and law
files are Markdown. It is allowed because it never runs in a consuming application: it ships
with the gem's tests, not with the gem's rules. Anything that runs in *your* build is a cop.

- **Principle:** `one-way-to-say-each-thing` governs — a second way to forbid something is a
  second thing that has to be kept correct, and the gap between the two is where the rule
  fails. `nothing-fails-quietly` produces the ratchet clause.
- **Guard:** `CanonTest`, in this gem's own suite — the exception above. Fails when a law
  names a cop that neither exists nor says it is unbuilt, when a cop exists that no law
  names, when a cop has no test, when a law states no limit, or when a law is missing from
  the index. It reads the cop registry rather than a checked-in list, so it cannot go
  stale.
- **Guard's limit:** it holds this canon's own wiring. **It cannot see a second mechanism a
  consuming application adds** — a rake task, a hook, a CI grep — because nothing in the
  application declares those as enforcement, and a check that guessed would be wrong more
  often than right. That half is a convention, and the ratchet is what makes keeping it
  attractive: a rule expressed as a cop gets a baseline and can be adopted, and a rule
  expressed as a script cannot.
