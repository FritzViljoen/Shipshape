# The patterns people reach for, and what this canon does instead

A survey, not a law. Rails teams escaping fat models and fat controllers reach for a fairly
stable set of patterns, and most of them are reaching for something real. This says, for each
one: what it is for, where it usually goes wrong, and what shipshape does about it.

Its companion, [what shipshape covers](rails-failure-patterns.md), takes the same subject from
the other end — the failures themselves, and which of them a guard actually catches.

**Two rules do most of the work below, and they are worth stating before the tables.** An
operation is sized by **authorisation** — it is an auth container, big enough to be permitted or
refused whole and no bigger — and split by **direction**, into a thing that writes and a thing
that reads. "How big should this service be?" and "may this one class do both?" are the two
questions the service-object pattern never answers, and most of what goes wrong downstream
follows from that.

**Otherwise the shape of nearly every answer here is the same: keep the half that was worth
having and refuse the half that costs.** CQRS is the clearest case. What it is for is that a read cannot
write and a write is not shaped like a read. What it costs is two models, two paths, and
projections nobody maintains. So this canon splits reads from writes **at the operation** —
`Command` and `Query`, enforced by `Shipshape/QueriesOnlyRead` — over one table, one record
class, one migration path. The separation survives; the freight does not.

Read the verdicts as:

| Verdict | Meaning |
|---|---|
| **Is this** | shipshape *is* the pattern, with its failure mode guarded |
| **Instead** | a different answer to the same need |
| **Refused** | shipshape says do not, and why |
| **Out of scope** | not a question about the shape of code |

---

## Usually work

| Pattern | Where it goes wrong | What this canon does |
|---|---|---|
| **Service objects** — one class, one `call`, logic out of controllers and models | Three ways. The `call` grows to 200 lines. You end up with 400 of them in one flat directory. And the one that compounds: services start calling services, which rewards splitting into ever smaller services that then need each other, until the call graph is real, undeclared and unreadable | **Is this, with a sizing rule and a direction.** What decides how big an operation is, is **authorisation**: it is an auth container, sized so it can be permitted or refused whole (`one-operation-one-class`), and split by direction into `Command` and `Query`. Sister calls are refused *before the matrix is consulted*, so no configuration can permit one — a command sequencing commands is a workflow that never said so, and a query composing queries is the read that becomes an N+1. The flat directory is the kind globs' business |
| **Result objects** — return `Success`/`Failure` rather than `true`/`nil`/raise | Nothing, except reaching for a gem to get twenty lines | **Is this.** `an-operation-answers-a-result`, and the `Result` is hand-rolled and installed into your repository — `code-is-written-not-generated`, because a base class you can read and edit beats a dependency you cannot |
| **Value objects** — `Money`, `EmailAddress`, `DateRange` as real types | Cheap and high payoff, and most teams never do it | **Is this.** `arguments-are-typed-at-construction` and `a-shape-is-composed-not-flattened` assume the types exist; [a primitive that should be a type](decomposing/a-primitive-that-should-be-a-type.md) is how you find the ones that should |
| **Query objects** — a complex scope chain in a class | Common advice is to return a relation, so the caller can chain further | **Is this, with one disagreement.** A `Query` returns **shapes, not relations**. A relation hands the caller a live record and an open invitation to keep querying, which is what `an-operation-is-a-leaf` and the call graph exist to stop. This is the one piece of usual advice here that shipshape rejects outright |
| **Form objects** — an `ActiveModel::Model` that validates and coordinates a multi-model save | Low risk, and it adds a second place a validation can live | **Instead.** The operation's constructor *is* the form object: `input-is-parsed-at-the-seam` parses the request, `TypedArguments` asserts each keyword. No extra class, and one home for the rule |
| **Policy objects** — authorisation out of controllers and views | Policies that hit the database on every call, and a second model of who may do what | **Instead.** A permission **is** the class name, checked by the base class before the work. The per-call query cannot arise: the demand is read from source at boot and memoised, and `rails shipshape:routes` prints what each endpoint needs |
| **Presenters / decorators** — wrap a model for the view | Draper's magic, or a wrapper that slowly acquires business logic | **Refused.** There is no presenter or decorator kind, deliberately — those dissolve. Markup goes to a view component, business logic to an operation, value formatting to the type itself. A component holds shapes and nothing else |
| **Concerns** — shared behaviour in a module | Used as "where I put code I didn't want in the model", so the class that includes it is where the size went | **Instead.** `Shipshape/MixinsAddNothingPublic`: a module mixed into an operation declares no public method. Two procedures for the rest — [a shared concern](decomposing/a-shared-concern.md) for behaviour, [a record concern](decomposing/a-record-concern.md) for the ones that oblige every including table to carry columns |

## Mixed results

| Pattern | Where it goes wrong | What this canon does |
|---|---|---|
| **Interactor / Trailblazer / dry-transaction** — composable steps with rollback | The team learns a DSL instead of Ruby, and debugging a failed step means reading through five layers | **Is this, minus the DSL.** `Workflow` is composable steps, and every base class installs into your repository as plain Ruby you own. A workflow's steps are read out of its own `call`, so there is no pipeline to learn and nothing between you and the stack trace |
| **State machines** — a gem, a status column, declared transitions | Modelling something that is not a state machine, and business logic buried in guard callbacks | **Instead.** [a state machine](decomposing/a-state-machine.md): a status column is usually a denormalisation of events that already happened. A transition table is the right instinct — that is the events being the truth. Guard callbacks are `no-lifecycle-callbacks` |
| **Observers / pub-sub** — decouple side effects from models | You can no longer answer "what happens when a user signs up" by reading code. The callback problem, now invisible | **Refused.** `nothing-travels-off-the-call-path` names it exactly: "publishing to a subscriber list resolved at runtime". [an event bus](decomposing/an-event-bus.md) walks it back and says which of the two things called event sourcing you actually have |
| **Repository pattern** — hide ActiveRecord behind an interface | You are fighting the framework, and you lose relations, scopes and eager loading to a mapping layer you now maintain for ever | **Refused.** A record maps rows and a query reads them *using* the framework — relations and eager loading all still work, inside the query. What does not escape is the record itself: a query answers shapes. That is the separation a repository wanted, with no interface and nothing to map |
| **Rails engines for modularity** | Fine when boundaries are genuinely separate; circular dependencies and a harder build when engines share models | **Out of scope.** Packaging, not shape. `Shipshape/CallGraph` gives the boundary the engines were reached for, without the build |
| **Packwerk / packs** — enforced module boundaries without extraction | Violations accumulate in a TODO file nobody drains | **Complementary.** Packwerk enforces package boundaries; shipshape enforces what a class is allowed to be. The TODO-file failure is what `shipshape check` answers by deriving its baseline from git rather than from a checked-in file — there is nothing to regenerate on a red build |

## Usually fail

| Pattern | Where it goes wrong | What this canon does |
|---|---|---|
| **CQRS** — separate read and write models | Two models, two paths, double the surface area, to solve an asymmetry a typical application does not have | **Is this, at one tenth the cost.** The split is at the **operation**, not the model: `Command` writes, `Query` reads, `QueriesOnlyRead` enforces it, and both use one table and one record class. No second model, no projections, no read path to keep in step |
| **Event sourcing** — events are the source of truth, state is a fold | Rebuilding is slow so it gets cached, and the cache quietly becomes the truth; schema versioning is brutal; every query needs a projection; and Rails assumes mutable rows everywhere | **Refused, with the exception stated.** [a stored derivation](decomposing/a-stored-derivation.md) and [an event bus](decomposing/an-event-bus.md) both open by asking what is lost if the event log is dropped. "Everything" means it is genuinely event-sourced, and neither procedure applies. "An audit trail" means it is pub-sub wearing the name — and every operation already records to the audit log |
| **Hexagonal / clean architecture** — ports, adapters, entities apart from AR | A mapping layer maintained for ever against a database you never actually swap | **Refused.** A record *is* the mapping and a shape is the domain object. The only adapters are `io_command` and `io_query`, and those are operations on the call graph rather than a layer wrapped around the application |
| **Micro-services extracted early** | Network calls where a method call would do, distributed transactions, and every bug becomes a tracing exercise | **Out of scope.** But the boundary that was wanted is `Shipshape/CallGraph`, declared once as a matrix, with nothing between the halves to go down |
| **DCI** — `extend` modules onto instances at runtime | Destroys the method cache and makes stack traces unreadable | **Refused.** `Shipshape/NoGeneratedInterfaces`: a method a reader greps for and never finds |

---

## The advice this canon half agrees with

The usual conclusion, and it is a reasonable one, is: **boring Rails plus discipline** — service
objects for orchestration, query objects for reads, form objects for input, jobs for anything
slow, and structure added when a specific pain appears rather than in advance.

**Half of that is exactly right.** Add structure when the pain appears: every procedure in
[the playbook](decomposing/README.md) is written for code that already hurts, and
`shipshape check` bills you for new violations rather than inherited ones so that nothing has to
be fixed in advance.

**The other half is why this gem exists.** Discipline is the part that does not survive a team
and a year. `one-mechanism-guards-everything` is the claim that a convention nobody enforces in
CI is indistinguishable from a convention nobody has — and every pattern above is a convention
until something fails the build over it.

Two details of that advice are refused outright:

- **`after_commit` rather than `after_save`.** Callbacks are banned, not relocated. Moving the
  trigger later keeps everything that made it unreadable.
- **"POROs for domain logic."** Yes — and they are `Shape`s that hold no records, which is the
  part that decides whether the PORO stays one.

## What this document is not

**It is not a verdict on your application.** A pattern refused here may be right where you are,
and every answer above assumes the rest of the canon. Taking one row alone — dropping Pundit
without base-class permissions, or returning shapes from queries without a call graph — buys the
cost and none of the benefit.

**And it is not measured.** [The failure survey](rails-failure-patterns.md) counts rows against
cops that exist. This one says what a canon *does about a practice*, which is a judgement. Where
a row names a guard, that guard is real; where it names a procedure, that procedure is prose and
holds nothing on its own.
