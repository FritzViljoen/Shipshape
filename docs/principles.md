# Principles

*How the code is shaped. Above the laws — we **follow** these; the laws are what we
**obey**.*

> **Nothing checks a principle, and nothing can.** "Is this one concern or three?" is a
> judgement, not a predicate. What is checkable is the *law* a principle produces, and
> every guard is named beside its law, never here.
>
> Each principle ends with what it produces. A principle that produces no law is either
> not true enough to act on, or a law nobody has written yet — both are defects, and
> both are visible from that line.

---

### `one-thing-one-place` — One thing, one place, reachable from every caller

Every operation, rule and fact has exactly one home, and every caller can reach it. A
rule a caller cannot reach gets copied, and the copy drifts.

So "where does this go" has one answer, and "where is this" has one answer. That pairing
is what makes a change finishable: you can tell you found every site, because there was
only ever one.

Two reasons to edit a file means two things sharing one home. Optional columns piling up
on a table is the same tell in the schema — several concepts sharing a row, with the
nulls marking the seam.

*Produces* `absence-is-absence`, `no-database-defaults`, and the placement laws.

### `good-boundaries-make-good-neighbours` — A boundary states what crosses it, and asserts it there

A boundary is a promise about what may pass. Where the promise is stated, it is checked;
past that line nothing re-checks, and a failure has a side — before the boundary it is
the caller's defect, after it the callee's.

An object is handed the values its decision needs, and nothing else. Not a whole record
to read one field, not a connection so it can find its own collaborators. What it
depends on arrives as an argument, because the caller is the thing that knows where it
is running.

That is what makes a rule testable without a database and usable from a second caller.
It is also what stops a change to one side of the boundary being a change to both.

*Produces* `arguments-are-typed-at-construction`, `input-is-parsed-at-the-seam`,
`a-time-names-its-zone`.

### `tell-dont-ask` — Send the message; do not pull the state out and decide for it

Ask an object a question, branch on the answer, and you have taken a responsibility that
belonged to the thing you asked. It now has two owners and they will disagree.

The general form of most of what follows: storage holds data rather than answering
questions about it; request handling dispatches rather than deciding; an operation
reports what happened rather than being interrogated about it.

Branching **is** asking. So a conditional at a call site is usually a rule that has
escaped its home, and the fix is to move the rule, not to tidy the conditional.

*Produces* `no-lifecycle-callbacks`, `no-decisions-in-request-handling`.

### `extend-by-adding` — A new case is a new object, not another branch

A new case should arrive as something the existing code already knows how to call, not
as a branch inside a method that has to be re-read and re-tested.

**With a stopping rule, because the opposite failure is real.** Where a rule genuinely
has a fixed, small set of cases — three outcomes, not an open family — a plain
conditional is honest, and an abstraction invented to avoid it is not. The test is
whether the set is expected to grow.

An abstraction earns its place by removing a way to say something. One that adds a way
has made things worse while looking like architecture.

*Produces* `one-operation-one-class`.

### `one-way-to-say-each-thing` — Variation is the defect; repetition is not

Twenty identical lines are greppable and safe to change at once. Two ways of expressing
one operation mean every rule about that operation must know both — and the third way is
invisible until it fails.

So an operation answers the same way everywhere. A uniform shape is what lets one wrapper
serve every call site: logging, instrumentation, an audit trail, a migration seam. Four
call conventions and none of them can exist.

This is also the working form of substitutability. Anything accepting a type must work
with every kind of it without asking which one it has; a variant that raises where its
sibling returns is a different thing wearing the name.

Never scope work by diff size. One transform across a hundred files is a small change;
six files holding five judgements is a large one. Count the decisions.

*Produces* `one-shape-per-operation`, `no-type-interrogation`.

### `nothing-is-hidden` — Every rule is written where a reader greps for it

No macro that writes the initializer. No callback that runs behind `save`. No convention
that only someone who was in the room can see.

Generation compresses the writing and expands the reading. That was a good trade when
writing was the expensive half. It is not one now: the cost is paid on every read, by
every reader, forever — and the writer never pays it.

An interface that looks simpler than the thing behind it has moved the difficulty rather
than removed it, and moved it somewhere nobody is looking.

The measure is whether a reader can tell where a thing lives, what it does, and whether a
change to it is finished — **without reading it**. Predictable beats short.

*Produces* `code-is-written-not-generated`, `no-lifecycle-callbacks`, and the delivered
rule files.

### `make-the-wrong-thing-impossible` — Encode the rule; do not write it down and hope

A convention is a promise someone has to remember. A failing build is not.

Where a rule matters, it is a unique index, a NOT NULL column, a required keyword, a cop
that reddens CI. A rule the database does not know is a rule the database will break; a
validation is a courtesy to the user, the constraint is what makes the rule true.

**And every guard needs a test proven to fail** — delete the guard, watch it go red,
restore it. An unproven guard reads as coverage while catching nothing, which is worse
than no guard at all.

*Produces* every law's guard, and the rule that each guard is tested by removal.

### `nothing-fails-quietly` — An operation completes, or says why it did not

Silence is the failure mode to design out. A rescue that swallows. A cast that coerces
rubbish into a plausible value. A guard that skips the file it could not parse. A check
that passed because it was never asked.

A half-applied change is worse than a refused one, so a change that spans records is one
transaction — or, where it cannot be, every step is idempotent and every intermediate
state is a legal one.

**A guard states what it does not cover.** A blind spot nobody wrote down is read as
coverage, and a green build then means less than nothing.

*Produces* `a-guard-states-its-limit`, `no-silent-coercion`.

---

## Where SOLID went

Asked for, and worth stating plainly: the five are here, but not one-to-one. Three of
them are the same idea about dependencies, and keeping them apart would have cost three
slots to say one thing.

| SOLID | Here |
|---|---|
| Single responsibility | `one-thing-one-place` |
| Open/closed | `extend-by-adding`, with an explicit stopping rule |
| Liskov substitution | `one-way-to-say-each-thing` — substitutability is what a uniform shape buys |
| Interface segregation | `good-boundaries-make-good-neighbours` |
| Dependency inversion | `good-boundaries-make-good-neighbours` |

What SOLID does not carry, and this canon does: `tell-dont-ask`, `nothing-is-hidden`,
`make-the-wrong-thing-impossible`, `nothing-fails-quietly`. Four of eight. SOLID says how
objects are shaped; it says nothing about whether the shape can be seen, or held.
