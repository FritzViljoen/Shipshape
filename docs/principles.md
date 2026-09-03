# Principles

*How the code is shaped. Above the laws — we **follow** these; the laws are what we
**obey**.*

> **Nothing checks a principle, and nothing can.** "Is this one concern or three?" is a
> judgement, not a predicate. What is checkable is the *law* a principle produces, and
> every guard is named beside its law, never here.
>
> **Each principle states its grounding.** A principle held because someone prefers it is
> a taste, and a canon of tastes cannot ask anyone to obey it. Where the published
> evidence is mixed, or points the other way, that is written here rather than left out —
> see `nothing-is-hidden`, where a respected source disagrees, and
> `one-way-to-say-each-thing`, which rests on a prediction and states what would falsify it.
>
> Each also ends with what it produces. A principle that produces no law is either not
> true enough to act on, or a law nobody has written yet. Both are defects, and both are
> visible from that line.

Full citations are in [References](#references). Which of them were checked, and which
are quoted from memory, is stated there.

---

### `good-boundaries-make-good-neighbours` — One home, and which homes may reach which is declared

Every operation, rule and fact has exactly one home. A rule a caller cannot reach gets
copied, and the copy drifts. So "where does this go" has one answer, and "where is this"
has one answer — the pairing that makes a change finishable, because you can tell you
found every site.

**Reachability has two failure modes, not one.** A rule its callers cannot reach gets
copied. A rule everything can reach becomes the place unrelated things are put, and then
it has many reasons to change — the same defect arrived at from the opposite side. So the
kinds that may call each other are **declared**, once, as a matrix: one home, reachable by
exactly the callers that should reach it.

Two reasons to edit a file means two things sharing one home. Optional columns piling up
on a table is the same tell in the schema — several concepts sharing a row, with the nulls
marking the seam.

**And reachability is symmetric, which is the half usually left out.** Nothing enters an
operation except through its arguments; nothing changes except what was handed in and what
is returned. An ambient read — the current time zone, the current user, a setting fetched
mid-operation — and a distant write — a global mutated, a class attribute set, an event
whose subscribers are discovered at runtime — are the same defect facing opposite ways: a
dependency that is not on the call path.

That is what action at a distance is, and why nothing else here catches it. The cause is
perfectly visible; it is the *effect* that cannot be found by reading. A reader can follow
what a call does only if what it does is bounded by what it was given.

**Grounding.** Placement is Parnas's decomposition criterion, older than "single responsibility": modules are
drawn around the decisions they hide, so a changed decision touches one module (Parnas 1972).
Chidamber and Kemerer made cohesion and coupling measurable; Basili, Briand and Melo validated
them as defect predictors across eight C++ systems (Basili et al. 1996). Reachability is the Law
of Demeter (Lieberherr and Holland 1989). The symmetric half is older still: Wulf and Shaw
nominated the non-local variable for abolition as a major contributor to programs that are hard
to understand (SIGPLAN Notices, 1973). Meyer's command-query separation is the same boundary
again (Meyer 1988).

*Produces* `the-call-graph-is-declared`, `nothing-travels-off-the-call-path`.

### `nothing-crosses-unasserted` — What crosses a boundary is stated there, and checked there

A boundary is a promise about what may pass. Where the promise is stated, it is checked;
past that line nothing re-checks, and a failure has a side — before the boundary it is the
caller's defect, after it the callee's. Re-checking inside is not caution; it is a second
place deciding the same thing.

An object is handed the values its decision needs, and nothing else. Not a whole record to
read one field, not a connection so it can find its own collaborators. What it depends on
arrives as an argument, because the caller is the thing that knows where it is running.

That is what makes a rule testable without a database and usable from a second caller. It
is also what stops a change to one side of a boundary being a change to both.

**The assertion is written where it happens.** A guard that runs somewhere else, or that a
macro generated, moves the failure away from the line that caused it — which is the one
place a reader will look.

**Grounding.** Meyer's Design by Contract states it as an obligation with a side: the precondition is the
caller's to meet, and the callee may assume it (Meyer 1988). The counter-tradition is Postel's
"be liberal in what you accept" — and the IETF's own later assessment is that this hurts,
because tolerated variation becomes load-bearing and can never be withdrawn (Thomson, *The
Harmful Consequences of the Robustness Principle*). Meyer wins here: an interface that accepts
what it cannot state has no boundary, only a habit.

*Produces* `arguments-are-typed-at-construction`, `input-is-parsed-at-the-seam`,
`a-time-names-its-zone`.

### `absence-is-absence` — A gap is not a value

Where a fact has not been stated, nothing is stored. A null is not "off", not "inherit",
not "not applicable", not "we lost it" — it is every one of those at once, and no reader
can tell which. Each meaning given to it is a fact nobody declared.

So a column is NOT NULL, and the way to say "nobody has said" is the absence of a row.
A nullable foreign key is usually two things sharing one table; a join with a uniqueness
constraint says the same thing and can be read.

**The mirror defect is a fact stated twice.** A gap given a meaning is a fact nobody
declared; a column default beside a model default is one fact declared twice, and the two
drift. Both leave a reader unable to say what the system holds — one because nothing
states it, the other because two things do and they disagree. A fact is stated once,
somewhere a reader can name.

**Grounding.** Hoare calls the null reference his billion-dollar mistake, added to ALGOL W in 1965 because it
was easy to implement (QCon London, 2009). Codd introduced nulls to the relational model; Date
and Darwen rejected them, because three-valued logic produces results no user can interpret. The
industry has been paying to undo it since: option types in ML and Rust, Kotlin's null-safe
types, Swift's optionals, C#'s nullable references, and NullAway at Uber and Nullsafe at Meta.

**The schema half is weaker.** That a nullable column marks two concepts sharing a table is
Parnas's cohesion argument applied to data, not a measured result. It has predicted well in
practice, which is a weaker warrant than the paragraph above.

*Produces* `absence-is-absence-never-a-value`, `no-database-defaults`.

### `model-concerns-not-groups` — A shared noun is not a shared concern

A god object is a **grouping**. Everything that mentions the noun lands on one class,
because the noun was the filing rule, and after a decade it is a hundred columns wide and
nobody can say what it is. Nothing decided that. It accreted, one reasonable addition at a
time.

**Two moves, and they are one idea.**

**Persistence is separated from the thing.** A record maps rows and holds no rules. The
domain object is built by an operation, composed, and detached from the database — so a
reader holding one cannot accidentally query or write through it, and the thing's shape
stops being whatever the table happens to have.

**Objects compose rather than flatten.** A domain object holds another domain object as a
field; it never copies that object's attributes onto itself. A flattened field is the first
column of the next god object.

**The tell is in the schema before it is in the class.** Attributes that apply to only some
rows are two concepts sharing a table, and the nulls mark the seam — which is why
`absence-is-absence` catches this defect one layer down.

**And a god object comes apart along the concerns that own it**, never by being moved
wholesale somewhere better. Relocating a grouping produces a grouping.

**Grounding.** Lanza and Marinescu make it operational: God Class is high foreign-data access, high complexity
**and low cohesion together** — cohesion, not size, is the defining term. Khomh et al. measured
the consequence across real systems: classes in antipatterns are more change- and fault-prone,
and **size alone cannot explain the difference** (ESE 2012). Composition over flattening is
Evans.

**The tension.** Fowler's *anemic domain model* argues against exactly this separation, and here
behaviour does live in operations rather than on the record, so the objection lands. The answer:
his target is a procedural script with no model, where here the operations are named domain
concepts and the values are typed. What decides it is whether operations carry domain names or
CRUD names, and no check makes that call.

Where the shared noun is a word the business owns, the concern belongs in rows —
`no-industry-terms-in-code`, which is the one to check first because it shrinks the class before
anything moves.

*Produces* `persistence-holds-no-behaviour`, `a-shape-is-composed-not-flattened`.

### `no-industry-terms-in-code` — A word the business owns is a row, not a branch

`vat`, `tourism_levy`, `gold_tier`, `draft`, `card_payment`. If somebody outside the team
owns the word, it belongs in the database.

**The test is who you ask when it is wrong.** A person — an accountant, an operations
manager, the client — means it is data. A programmer means it is control flow and stays.
"Is it a constant?" is the failing question, because constants are code; `RATES = {...}` is
still a deploy away from being right.

**This is the same defect wearing several costumes**, and naming it once is what makes the
costumes recognisable:

- single-table inheritance is a **type column** written as classes
- a state machine is a **transition table** written as branches
- lifecycle callbacks are an **ordering** written as registration order
- a `case` over levy names is a **rate table** written as a method

Each began the same way: somebody had a set of facts that grows — statuses, tiers, rates,
steps — and no place to put facts, so they went in the only place the framework offered,
which was more code.

**The cost is not ugliness, it is the growth curve.** Code that encodes facts grows every
time the *facts* grow, and that is the one kind of growth refactoring never fixes, because
the code was never the problem. A fifteen-method service split into fifteen classes still
has the branch; it is now in one of them, and adding a levy is still a deploy. **So this
comes before any decomposition**, not after.

**What you get back is not tidiness.** A term the business owns, held as data, can be added
without a deploy, differ per tenant, be listed on a screen, be totalled in a report, and be
corrected by the person who knows the answer. Held as code it can do none of those, and each
one becomes a ticket.

**Grounding.** Parnas's criterion read literally: decompose around the decisions likely to change, and a
business vocabulary is the fastest-changing thing in a commercial codebase. Evans's ubiquitous
language argues the domain's words belong in the model; this adds *where* — in rows, because the
people who own the words cannot edit Ruby. The failure mode is Evans's *anaemic* one inverted:
behaviour that has swallowed the model's vocabulary.

**The limit.** Some vocabularies are structural. A payment clearing through a different network
needs different code, not a different row, and forcing it into data produces a configuration
language nobody can debug. The signal you have gone too far is a row whose value is the name of
a class.

*Produces* the "Rules that are really data" measure, and the shared first step of every
procedure in [`docs/decomposing/`](decomposing/).

### `tell-dont-ask` — Send the message; do not pull the state out and decide for it

Ask an object a question, branch on the answer, and you have taken a responsibility that
belonged to the thing you asked. It now has two owners and they will disagree.

The general form of most of what follows: storage holds data rather than answering
questions about it; request handling dispatches rather than deciding; an operation
reports what happened rather than being interrogated about it.

Branching **is** asking. So a conditional at a call site is usually a rule that has
escaped its home, and the fix is to move the rule, not to tidy the conditional.

**Which puts an obligation on the other side, and this is the half that gets dropped.**
A caller forbidden to interrogate is a caller that cannot discover a failure on its own.
So the callee must report — every outcome the caller is entitled to act on comes back as
a value, not as a state to be inspected afterwards. Tell-don't-ask without
`nothing-fails-quietly` is just silence with better manners.

**Grounding.** The formulation is Sharp's, carried by Hunt and Thomas and set out by Fowler. The measurable
form is the Law of Demeter, whose whole content is that reaching through an object to decide on
its behalf couples you to its internals (Lieberherr and Holland 1989). It is also the diagnosis
behind *feature envy* and *anemic domain model* (Fowler).

*Produces* `no-lifecycle-callbacks`, `no-decisions-in-request-handling`.

### `one-way-to-say-each-thing` — One operation, one class, one way to call it

An operation is a class with one public method. It answers the same way everywhere.

A uniform shape is what lets one wrapper serve every call site: logging, instrumentation,
an audit trail, a migration seam. Four call conventions and none of those can exist. It is
also the working form of substitutability — anything accepting a type must work with every
kind of it without asking which one it has (Liskov and Wing 1994), and a variant that
raises where its sibling returns is a different thing wearing the name.

**A new case is therefore a new class, not another branch.** Not by exhortation: a
single-method class has nowhere to grow a branch, and the declared call graph gives the
branch nowhere to reach. The open/closed principle falls out of the shape rather than
being asked for.

**With a stopping rule, because the opposite failure is real.** Where a rule genuinely has
a fixed, small set of cases — three outcomes, not an open family — a plain conditional
inside the operation is honest, and an abstraction invented to avoid it is not. The test
is whether the set is expected to grow. An abstraction earns its place by removing a way
to say something; one that adds a way has made things worse while looking like
architecture.

Never scope work by diff size. One transform across a hundred files is a small change; six
files holding five judgements is a large one. Count the decisions.

**Grounding.** Engler et al. inferred bugs from *deviation*: where code implies a belief the programmer must
hold, the sites contradicting the dominant pattern are the defects — found across
operating-system code with no specification at all (SOSP 2001). Variation is the signal a
detector runs on. Open/closed is Meyer (1988), restated by Martin (1996); the stopping rule is
the literature's own, since Fowler names *speculative generality* a smell and a wrong
abstraction is harder to remove than a conditional is to add.

**On duplication this is a prediction, not a finding.** Industry telemetry reports duplicated
blocks rising eightfold in 2024, with moved-and-refactored code falling from 24.8% of changed
lines in 2021 to 9.5% (GitClear 2025). The claim here is that the shape prevents that
structurally: when the unit is a one-method class and the call graph is declared, a shared step
has nowhere to live but its own class, and a thousand-line file cannot form. **Untested** — that
telemetry measures codebases with no such constraint, so it can neither confirm nor refute it.
What would falsify it: near-identical bodies across sibling operation classes.

*Produces* `one-operation-one-class`, `no-type-interrogation`.

### `nothing-is-hidden` — Every rule is written where a reader greps for it

No macro that writes the initializer. No callback that runs behind `save`. No convention
that only someone who was in the room can see.

Generation compresses the writing and expands the reading. That was a good trade when
writing was the expensive half. It is not one now: the cost is paid on every read, by
every reader, forever — and the writer never pays it.

The measure is whether a reader can tell where a thing lives, what it does, and whether a
change to it is finished — **without reading it**. Predictable beats short.

**Grounding.** Reading dominates. Xia et al. instrumented 78 developers over 3,148 working hours across seven
real projects and found roughly 58% of working time goes to program comprehension (TSE 2018);
Minelli et al. report a comparable share from IDE interaction data (ICPC 2015). Any construct
trading reading cost for writing cost trades against the larger number. The generation-cost
collapse that sharpens this is industry telemetry rather than peer-reviewed — GitClear's 2025
analysis of 211 million changed lines — and should be cited as such.

**The tension.** Ousterhout argues for *deep* modules and would call some of what this forbids
good design. The distinction: hiding an implementation is Parnas's point and is right; hiding
*where the rule is written* defeats the reader looking for it. A deep module whose interface is
greppable satisfies both. A macro that generates the interface satisfies neither.

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

**Grounding.** Poka-yoke from the Toyota Production System (Shingo): shape the fixture so the part cannot be
fitted the wrong way round, rather than training the operator. Minsky's "make illegal states
unrepresentable" is the same move in a type system. The delivery half is settled empirically:
Sadowski et al. report that at Google, filing tool-found bugs as tickets did not scale — 84%
went unfixed — and what worked was surfacing findings in the workflow, at review time, on a low
false-positive budget (CACM 2018). A guard nobody is forced to look at is not a guard, which is
the argument for the ratchet.

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

**This is the other half of `tell-dont-ask`.** A caller that may not interrogate can only
know what it is told, so every outcome it is entitled to act on has to come back as a
value. The two principles are one exchange: one forbids the question, the other obliges
the answer. Drop either and the pair becomes a caller guessing.

**Grounding, and it is the best-evidenced principle here.** Yuan et al. analysed 198
randomly sampled real-world failures across five distributed systems and found that 92% of
catastrophic failures came from incorrect handling of errors that had already been
signalled — and that in 58% of them the underlying fault would have been caught by simple
testing of the error-handling path. A third of the catastrophic cases were trivial: an
empty handler, a bare log, a `TODO` (OSDI 2014). The failure mode is not the unknown
error; it is the known error, swallowed. Shore's "Fail Fast" (IEEE Software, 2004) is the
prescription. The compensation half — where one transaction is impossible, every step is
idempotent and every intermediate state legal — is the saga, from Garcia-Molina and Salem
(SIGMOD 1987).

*Produces* `a-guard-states-its-limit`, `no-silent-coercion`.

---

## References

**Checked against the published record while this document was written:**

- Engler, Chen, Hallem, Chou, Chelf. *Bugs as Deviant Behavior: A General Approach to
  Inferring Errors in Systems Code.* SOSP 2001.
  https://dl.acm.org/doi/10.1145/502034.502041
- Yuan et al. *Simple Testing Can Prevent Most Critical Failures.* OSDI 2014.
  https://www.usenix.org/system/files/conference/osdi14/osdi14-paper-yuan.pdf
- Xia, Bao, Lo, Xing, Hassan, Li. *Measuring Program Comprehension: A Large-Scale Field
  Study with Professionals.* IEEE TSE 44(10), 2018.
  https://ieeexplore.ieee.org/document/7997917/
- Sadowski, Aftandilian, Eagle, Miller-Cushon, Jaspan. *Lessons from Building Static
  Analysis Tools at Google.* CACM 61(4), 2018. https://dl.acm.org/doi/10.1145/3188720
- GitClear. *AI Copilot Code Quality: 2025 Research.* Industry telemetry, not
  peer-reviewed. https://www.gitclear.com/ai_assistant_code_quality_2025_research
- Wulf, Shaw. *Global Variable Considered Harmful.* ACM SIGPLAN Notices 8(2), Feb 1973,
  28–34. https://dl.acm.org/doi/10.1145/953353.953355
- Lanza, Marinescu. *Object-Oriented Metrics in Practice.* Springer, 2006 — the God Class
  detection strategy. https://link.springer.com/book/10.1007/3-540-39538-5
- Khomh, Di Penta, Guéhéneuc, Antoniol. *An exploratory study of the impact of antipatterns
  on class change- and fault-proneness.* Empirical Software Engineering, 2012.
  https://link.springer.com/article/10.1007/s10664-011-9171-y
- Hoare. *Null References: The Billion Dollar Mistake.* QCon London 2009.
  https://www.infoq.com/presentations/Null-References-The-Billion-Dollar-Mistake-Tony-Hoare/

**Cited from the standing literature, not re-checked here.** Each is well known enough
that the risk is a wrong year or a wrong venue, not a work that does not exist. Verify
before quoting any of them in print.

- Parnas. *On the Criteria To Be Used in Decomposing Systems into Modules.* CACM, 1972.
- Chidamber, Kemerer. *A Metrics Suite for Object Oriented Design.* IEEE TSE, 1994.
- Basili, Briand, Melo. *A Validation of Object-Oriented Design Metrics as Quality
  Indicators.* IEEE TSE, 1996.
- Meyer. *Object-Oriented Software Construction.* 1988 — Design by Contract, open/closed.
- Lieberherr, Holland. *Assuring Good Style for Object-Oriented Programs.* IEEE Software,
  1989 — the Law of Demeter.
- Liskov, Wing. *A Behavioral Notion of Subtyping.* ACM TOPLAS, 1994.
- Martin. *The Open-Closed Principle.* C++ Report, 1996.
- Fowler. *Refactoring* — speculative generality, feature envy, large class; and the
  *TellDontAsk* and *AnemicDomainModel* bliki entries, the latter being the standing
  objection named under `model-concerns-not-groups`.
- Evans. *Domain-Driven Design*, 2003 — shapes and value objects composed into
  aggregates.
- Hunt, Thomas. *The Pragmatic Programmer*, 1999 — tell, don't ask.
- Shore. *Fail Fast.* IEEE Software, 2004.
- Garcia-Molina, Salem. *Sagas.* SIGMOD 1987.
- Shingo. *Zero Quality Control: Source Inspection and the Poka-Yoke System*, 1986.
- Date, Darwen. *The Third Manifesto* — the case against nulls in the relational model.
- Minsky. *Effective ML* — make illegal states unrepresentable.
- Ousterhout. *A Philosophy of Software Design*, 2018 — deep modules, and the tension
  named under `nothing-is-hidden`.
- Thomson. *The Harmful Consequences of the Robustness Principle.* IETF draft.
- Minelli, Mocci, Lanza. *I Know What You Did Last Summer.* ICPC 2015.
