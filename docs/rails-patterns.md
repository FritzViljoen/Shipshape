# The patterns people reach for, and what this canon does instead

A survey, not a law. Its companion, [what shipshape covers](rails-failure-patterns.md), takes a
list of ways Rails applications *fail*. This one takes a list of the patterns teams *reach for*
to stop them failing, assembled independently of this canon, and says for each what shipshape
does about it.

**The shape of nearly every answer is the same: take the half that was worth having and refuse
the half that costs.** CQRS is the clearest case. Its useful half is that a read cannot write
and a write is not shaped like a read. Its expensive half is two models, two paths, projections
nobody maintains. So this canon splits reads from writes **at the operation** — `Command` and
`Query`, enforced by `Shipshape/QueriesOnlyRead` — over one table, one record class, one
migration path. You keep the separation and pay none of the freight.

Read the verdicts as:

| Verdict | Meaning |
|---|---|
| **Is this** | shipshape *is* the pattern, with the failure mode named and guarded |
| **Instead** | a different answer to the same need |
| **Refused** | shipshape says do not, and why |
| **Out of scope** | not a question about the shape of code |

---

## Usually work

| Pattern | Verdict | What this canon does |
|---|---|---|
| **Service objects / commands** | **Is this** | `Command`: one class, one public method, typed arguments, a `Result`. The failure mode the list names — 200-line `call`s, 400 of them with no structure — is `one-operation-one-class` and the kind globs, which make namespacing by domain the thing the layout is made of rather than a convention |
| **Result objects** | **Is this** | `an-operation-answers-a-result`, and a hand-rolled `Result` rather than dry-monads — `code-is-written-not-generated`, because a base class you can read and edit beats a dependency you cannot |
| **Value objects** | **Is this** | `arguments-are-typed-at-construction` and `a-shape-is-composed-not-flattened`. "Most teams skip it" is the gap [a primitive that should be a type](decomposing/a-primitive-that-should-be-a-type.md) exists to close |
| **Query objects** | **Is this, with one disagreement** | `Query` is exactly this. But it returns **shapes, not relations** — a relation hands the caller a live record and an open invitation to keep querying, which is the thing `an-operation-is-a-leaf` and the call graph exist to stop. "Keep them returning relations" is the one line here this canon rejects outright |
| **Form objects** | **Instead** | The operation's constructor is the form object. `input-is-parsed-at-the-seam` parses the request; `TypedArguments` asserts each keyword. No `ActiveModel::Model` class, and no second place for a validation to live |
| **Policy objects (Pundit)** | **Instead** | A permission **is** the class name, checked by the base class before the work. The failure mode named — "policies that query the DB per call" — cannot arise: the demand is read from source at boot and memoised, and `CallGraph.routes` prints what each endpoint needs |
| **Presenters / decorators** | **Refused** | There is no presenter or decorator kind, deliberately: those dissolve. Markup goes to a view component, business logic to an operation, value formatting to the type. A component holds shapes and nothing else |
| **Concerns** | **Instead** | `Shipshape/MixinsAddNothingPublic`: a module mixed into an operation declares no public method. "Where I put code I didn't want in the model" has two procedures — [a shared concern](decomposing/a-shared-concern.md) for behaviour, [a record concern](decomposing/a-record-concern.md) for the ones that oblige columns |

## Mixed results

| Pattern | Verdict | What this canon does |
|---|---|---|
| **Interactor / Trailblazer / dry-transaction** | **Is this, minus the DSL** | `Workflow` is composable steps. The cost the list names — "the team learns a DSL instead of Ruby" — is why every base class is installed into your repository as plain Ruby you own, and why a workflow's steps are read from its `call` rather than declared in a pipeline |
| **State machines** | **Instead** | [a state machine](decomposing/a-state-machine.md): a status column is usually a denormalisation of events that already happened. Statesman's transition table is the right instinct — it is the events being the truth. The failure mode named, "business logic buried in guard callbacks", is `no-lifecycle-callbacks` |
| **Observers / pub-sub** | **Refused** | `nothing-travels-off-the-call-path` names it exactly: "publishing to a subscriber list resolved at runtime". [an event bus](decomposing/an-event-bus.md) walks it back. The list's own diagnosis — "you can no longer answer what happens when a user signs up by reading code" — is the whole argument |
| **Repository pattern** | **Refused, and for the reason the list gives** | You would be fighting the framework. A record maps rows and a query reads them *using* the framework — relations, eager loading, scopes all still work, inside the query. What does not escape is the record itself: the query answers shapes. That is the separation a repository wanted, without an interface or a mapping layer |
| **Rails engines** | **Out of scope** | Packaging, not shape. `Shipshape/CallGraph` gives the boundary the engines were for without the build cost |
| **Packwerk / packs** | **Complementary** | Packwerk enforces package boundaries; shipshape enforces what a class is allowed to be. The failure the list names — "violations accumulate in a TODO file" — is what `shipshape check` answers by deriving the baseline from git rather than from a checked-in file |

## Usually fail

| Pattern | Verdict | What this canon does |
|---|---|---|
| **CQRS** | **Is this, at one tenth the cost** | Reads and writes split **at the operation, not at the model**. `Command` writes and `Query` reads, `QueriesOnlyRead` enforces it, and both use one table and one record class. No second model, no projections, no read path to keep in step. The asymmetry the pattern exists for is real; the two-model machinery is what makes it fail |
| **Event sourcing** | **Refused, with one exception stated** | [a stored derivation](decomposing/a-stored-derivation.md) step 0 and [an event bus](decomposing/an-event-bus.md) step 0 both open by asking what is lost if the event log is dropped. "Everything" means it is a legitimate architecture and neither procedure applies. "An audit trail" means it is pub-sub wearing the name — and every operation already records to the audit log |
| **Hexagonal / clean architecture** | **Refused** | The mapping layer never pays for itself. A record is the mapping, a shape is the domain object, and the only "adapters" are `io_command` and `io_query` — which are operations on the call graph, not a layer around the application |
| **Micro-services extracted early** | **Out of scope** | But the boundary a team wanted is `Shipshape/CallGraph`, declared once as a matrix, with no network between the halves and no distributed transaction to be sorry about |
| **DCI** | **Refused** | `extend`-ing a module onto an instance at runtime is `Shipshape/NoGeneratedInterfaces`: a method a reader greps for and never finds |

---

## The conclusion is the one thing this canon contradicts

> Boring Rails plus discipline… Add structure when a specific pain appears, not in advance.

**Half of that is exactly right.** Add structure when the pain appears — every procedure in
[the playbook](decomposing/README.md) is written for code that already hurts, and
`shipshape check` bills you for new violations rather than inherited ones precisely so nothing
has to be fixed in advance.

**The other half is the thing shipshape exists because of.** Discipline is the part that does
not survive a team and a year. `one-mechanism-guards-everything` is the claim that a convention
nobody enforces in CI is indistinguishable from a convention nobody has — and every pattern on
this page is a convention until something fails the build over it.

Two details of that sentence this canon refuses outright:

- **`after_commit` instead of `after_save`** — callbacks are banned, not relocated. Moving the
  trigger later keeps everything that made it hard to read.
- **"POROs for domain logic"** — yes, and they are `Shape`s that hold no records, which is the
  part that decides whether the PORO stays a PORO.

## What this document is not

**It is not a verdict on your application.** A pattern refused here may be right where you are,
and the canon's answer assumes the rest of the canon. Taking one row in isolation — dropping
Pundit without base-class permissions, or returning shapes from queries without a call graph —
buys the cost and none of the benefit.

**And it is not measured.** [The failure survey](rails-failure-patterns.md) counts rows against
cops that exist; this one says what a canon *does about a practice*, which is a judgement. Where
a row names a guard, that guard is real and named; where it names a procedure, that procedure is
prose and holds nothing by itself.
