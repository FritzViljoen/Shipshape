# The patterns people reach for, and what this canon does instead

A survey, not a law. Rails teams escaping fat models and fat controllers reach for a fairly
stable set of patterns, and most of them are reaching for something real. This says, for each
one: what it is for, where it usually goes wrong, and **what you get here instead** — the
payoff, not just the mechanism.

Its companion, [what shipshape covers](rails-failure-patterns.md), takes the same subject from
the other end — the failures themselves, and which of them a guard actually catches.

**Two rules do most of the work below, and they are worth stating before the tables.** An
operation is sized by **authorisation** — it is an auth container, big enough to be permitted or
refused whole and no bigger — and split by **direction**, into a thing that writes and a thing
that reads. "How big should this service be?" and "may this one class do both?" are the two
questions the service-object pattern never answers, and most of what goes wrong downstream
follows from that.

**Otherwise the shape of nearly every answer here is the same: keep the half that was worth
having and refuse the half that costs.** CQRS is the clearest case. What it is for is that a
read cannot write and a write is not shaped like a read. What it costs is two models, two paths,
and projections nobody maintains. So this canon splits reads from writes **at the operation** —
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

| Pattern | Where it goes wrong | What you get here |
|---|---|---|
| **Service objects** — one class, one `call`, logic out of controllers and models | Three ways. The `call` grows to 200 lines. You end up with 400 of them in one flat directory. And the one that compounds: services start calling services, which rewards splitting into ever smaller services that then need each other, until the call graph is real, undeclared and unreadable | **Is this.** **You stop arguing about how big a service should be**, because authorisation decides it: an operation is an auth container, sized to be permitted or refused whole (`one-operation-one-class`), split by direction into `Command` and `Query`. **And services cannot multiply into each other** — sister calls are refused *before the matrix is consulted*, so no configuration permits one. A command sequencing commands is a workflow that never said so; a query composing queries is the read that becomes an N+1. **Not guarded:** the flat directory. Kinds come from path globs, so a per-domain layout is expressible and a misfiled class shows up in `shipshape coverage` — but nothing counts files, and 400 in one is legal |
| **Result objects** — return `Success`/`Failure` rather than `true`/`nil`/raise | Nothing much, except reaching for a gem to get twenty lines | **Is this, and it is what everything else stands on.** Every operation is called the same way and answers the same object: `X.call(actor:, **arguments)` → `Result`. **The uniformity is the payoff, not the tidiness.** It is why one base class adds the permission check, the audit entry, `call_later` and per-operation retries to *every* operation while knowing nothing about any of them — and why substituting one operation for another is a change at the call site and nowhere else. A caller holds the contract, never the class. The `Result` is hand-rolled and installed into your repository, because a base class you can read and edit beats a dependency you cannot |
| **Value objects** — `Money`, `EmailAddress`, `DateRange` as real types | Nothing goes wrong with it. Teams skip it, and then every rule that assumed the type exists has nowhere to live | **Is this, and it is what makes a view safe.** These are `Shape`s, and a shape holds no records — so what a query answers and hands onward carries values, never a live row. The call graph gives the view kind exactly one edge, to `shape`: *"it renders what it was handed and reads nothing."* **So a template cannot query.** The N+1 from a partial stops being possible rather than being caught afterwards, and "no database access in a view" stops being a review comment |
| **Query objects** — a complex scope chain in a class | Common advice is to return a relation, so the caller can chain further | **Is this, with one disagreement.** A `Query` returns **shapes, not relations**. **What you get is a read that ends where it says it ends**: the caller cannot extend it, cannot fire it lazily somewhere else, and cannot hold the record afterwards. A relation hands back a live row and an open invitation to keep querying, which is what the call graph exists to stop. This is the one piece of usual advice here that shipshape rejects outright |
| **Form objects** — an `ActiveModel::Model` that validates and coordinates a multi-model save | Low risk, and it adds a second place a validation can live | **Instead.** The operation's constructor *is* the form object. **What you get is one home for the rule and one shape of input**: `input-is-parsed-at-the-seam` parses the request, `TypedArguments` asserts every keyword, and the same operation is then reachable from a controller, a job and a scheduled request with no second validation path to keep in step |
| **Policy objects** — authorisation out of controllers and views | Policies that hit the database on every call, and a second model of who may do what | **Instead.** A permission **is** the class name, checked by the base class before the work. **What you get is authorisation you can read off the routes**: `rails shipshape:routes` prints what every endpoint demands, so the grants to seed are derived rather than remembered. The per-call query cannot arise — the demand is read from source at boot and memoised — and because the actor is a real actor, revoking a person stops the scheduled work they set running |
| **Presenters / decorators** — wrap a model for the view | Draper's magic, or a wrapper that slowly acquires business logic | **Refused.** There is no presenter or decorator kind, deliberately — those dissolve. **What you get is no third place for logic to collect**: markup goes to a view component, business logic to an operation, value formatting to the type itself, and each of those three is somewhere a reader can find it |
| **Concerns** — shared behaviour in a module | Used as "where I put code I didn't want in the model", so the class that includes it is where the size went | **Instead.** `Shipshape/MixinsAddNothingPublic`: a module mixed into an operation declares no public method. **What you get is a class whose surface you can read off the class** — including a module cannot quietly widen it. Two procedures for the rest: [a shared concern](decomposing/a-shared-concern.md) for behaviour, [a record concern](decomposing/a-record-concern.md) for the ones that oblige every including table to carry columns |

## Mixed results

| Pattern | Where it goes wrong | What you get here |
|---|---|---|
| **Interactor / Trailblazer / dry-transaction** — composable steps with rollback | The team learns a DSL instead of Ruby, and debugging a failed step means reading through five layers | **Is this, minus the DSL.** `Workflow` is composable steps. **What you get is your own stack trace**: every base class installs into your repository as plain Ruby you own, and a workflow's steps are read out of its own `call`, so there is no pipeline object between you and the failure and nothing to learn before reading one |
| **State machines** — a gem, a status column, declared transitions | Modelling something that is not a state machine, and business logic buried in guard callbacks | **Instead.** [a state machine](decomposing/a-state-machine.md): a status column is usually a denormalisation of events that already happened. **What you get is a state that cannot drift from the rows**, because it is derived from them — and history for free, since the events are the truth rather than a summary of it. A transition table is the right instinct; guard callbacks are `no-lifecycle-callbacks` |
| **Observers / pub-sub** — decouple side effects from models | You can no longer answer "what happens when a user signs up" by reading code. The callback problem, now invisible | **Refused.** `nothing-travels-off-the-call-path` names it exactly: "publishing to a subscriber list resolved at runtime". **What you get back is that question having an answer** — one workflow, in one file, in the order it runs. [an event bus](decomposing/an-event-bus.md) walks an existing one back, and starts by asking which of the two things called event sourcing you actually have |
| **Repository pattern** — hide ActiveRecord behind an interface | You are fighting the framework, and you lose relations, scopes and eager loading to a mapping layer you now maintain for ever | **Refused.** **What you get is the boundary without the mapping layer.** A record maps rows and a query reads them *using* the framework — relations and eager loading all still work, inside the query. What does not escape is the record itself: a query answers shapes. That is the separation a repository wanted, with no interface to write and nothing to keep in step |
| **Rails engines for modularity** | Fine when boundaries are genuinely separate; circular dependencies and a harder build when engines share models | **Out of scope.** Packaging, not shape. **What you get instead is the boundary without the build**: `Shipshape/CallGraph` declares which kind may call which, once, as a matrix |
| **Packwerk / packs** — enforced module boundaries without extraction | Violations accumulate in a TODO file nobody drains | **Complementary.** Packwerk enforces package boundaries; shipshape enforces what a class is allowed to be. **On the TODO-file problem, what you get is nothing to regenerate**: `shipshape check` derives its baseline from the merge-base every run, so there is no file to press a button on when the build goes red |

## Usually fail

| Pattern | Where it goes wrong | What you get here |
|---|---|---|
| **CQRS** — separate read and write models | Two models, two paths, double the surface area, to solve an asymmetry a typical application does not have | **Is this, at one tenth the cost.** The split is at the **operation**, not the model: `Command` writes, `Query` reads, `QueriesOnlyRead` enforces it. **What you get is the separation on one table, one record class and one migration path** — no second model, no projections, and no read path that can fall behind the write path, because there is only one |
| **Event sourcing** — events are the source of truth, state is a fold | Rebuilding is slow so it gets cached, and the cache quietly becomes the truth; schema versioning is brutal; every query needs a projection; and Rails assumes mutable rows everywhere | **Refused, with the exception stated.** **What you get is a one-sentence test for which thing you have**: what is lost if the event log is dropped? "Everything" means it is genuinely event-sourced, and neither [a stored derivation](decomposing/a-stored-derivation.md) nor [an event bus](decomposing/an-event-bus.md) applies. "An audit trail" means it is pub-sub wearing the name — and every operation already records to the audit log, which is what most teams wanted from it |
| **Hexagonal / clean architecture** — ports, adapters, entities apart from AR | A mapping layer maintained for ever against a database you never actually swap | **Refused.** **What you get is the same isolation with nothing to maintain**: a record *is* the mapping, a shape is the domain object, and the only adapters are `io_command` and `io_query` — operations on the call graph rather than a layer wrapped around the application |
| **Micro-services extracted early** | Network calls where a method call would do, distributed transactions, and every bug becomes a tracing exercise | **Out of scope.** **What you get is the boundary without the network**: `Shipshape/CallGraph`, declared once, with nothing between the halves that can be down |
| **DCI** — `extend` modules onto instances at runtime | Destroys the method cache and makes stack traces unreadable | **Refused.** **What you get is methods you can grep for.** `Shipshape/NoGeneratedInterfaces` fails a method a reader would search for and never find |

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
