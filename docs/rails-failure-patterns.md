# What shipshape covers, against a list it did not write

A survey, not a law. Somebody handed over a catalogue of about 120 ways Rails applications
fail, assembled independently of this canon, and the useful question is not "does shipshape
sound relevant" but **which rows it actually holds, and which it does not**.

The short answer: **it holds roughly half, and the half it holds is one half on purpose.**

---

## The dividing line is shape against runtime

**shipshape governs where code lives and what form it takes.** It reads files. It can tell you
that a rule is in a controller, that a record has a method, that a column admits a NULL, that a
module adds public surface. It cannot tell you that a page issued 400 queries, that a cache key
never expired, or that the connection pool is smaller than the thread count. Those are facts
about a running system, and a system that is running is the only thing that can report them.

So the catalogue splits cleanly, and the split is not an excuse:

- **Structural failures** — where a rule lives, what a class is allowed to be, what the schema
  admits. shipshape's whole subject. These compound: one rule in a controller is a nuisance,
  and the same rule in four controllers and a callback is why nobody can change it.
- **Runtime failures** — N+1, cache stampedes, memory bloat, table locks. Bullet, `strong_migrations`,
  an APM and a load test find these, and each of them finds them better than any file reader
  could. A canon that claimed them would be lying about its instruments.

**A guard that overstates its reach is worse than a missing guard**, because the missing one
leaves you looking. That is [`a-guard-states-its-limit`](laws/a-guard-states-its-limit.md), and
this document is that law applied to the whole canon at once.

---

## Four verdicts

| Verdict | What it means |
|---|---|
| **Unsayable** | The shape removes it. You cannot write the failure and stay inside the canon — there is no callback to put it in, no NULL to misread, no record to pass. |
| **Guarded** | A named cop fails the build on it. |
| **Procedure** | The playbook takes it apart, and no cop holds it. Judgement, with steps. |
| **Uncovered** | shipshape does not address it. The tool that does is named. |

**Unsayable is the strongest and the rarest**, and it is what
[`make-the-wrong-thing-impossible`](principles.md) is for. A cop is a guard you can disable; a
shape you cannot express is not a guard at all.

---

## Data layer

| Failure | Verdict | How |
|---|---|---|
| Missing `NOT NULL` on columns that require a value | **Guarded** | `Shipshape/NoNullableColumns` — every column, no exceptions list that grows |
| `where.not` with NULLs behaving unexpectedly | **Unsayable** | There are no NULLs to behave unexpectedly |
| Soft deletes without scoping every query | **Unsayable** | `deleted_at` is a nullable column and fails the build; [a nullable column](decomposing/a-nullable-column.md) models it as a row |
| Callbacks with side effects inside transactions | **Unsayable** | `no-lifecycle-callbacks` — there is no callback |
| Adding a column with a default, table lock | **Unsayable** | `Shipshape/NoColumnDefaults` — no column carries one |
| Validations without matching DB constraints | **Partly guarded** | Presence is forced into the schema by `NoNullableColumns`; **uniqueness races are uncovered** |
| Timezone columns stored inconsistently | **Guarded** | [`a-time-names-its-zone`](laws/a-time-names-its-zone.md), `Shipshape/NoAmbientReads` |
| Raw SQL string interpolation, SQL injection | **Partly guarded** | `NoUnparsedLookup` stops a raw param reaching a finder; raw SQL itself is **uncovered** → brakeman |
| Serialized columns that later need querying | **Procedure** | [a serialized column](decomposing/a-serialized-column.md) — a blob is an undeclared schema, and `NoNullableColumns` cannot see inside one |
| `default_scope` leaking into every query, and into `create` | **Guarded** | `Shipshape/PersistenceHoldsNoBehaviour` — a gap this survey found, now closed. It is implicit behaviour: global state in, distant write out |
| `unscoped` used to escape a bad `default_scope` | **Unsayable** | There is no `default_scope` left to escape |
| N+1 queries | **Uncovered** | Bullet, prosopite. Reads live in named `Query` classes, so the fix has one home — that is all |
| Missing indexes | **Uncovered** | `lol_dba`, `strong_migrations` |
| `dependent: :destroy` on huge associations | **Uncovered** | And note the tension: `AssociationsSurviveErasure` *demands* a `dependent:`, for erasure, which can make this worse |
| Enum as array, reordering remaps rows | **Uncovered** | — |
| Counter drift, `find_each` ignored, `pluck` vs `select` | **Uncovered** | Runtime and volume, not shape |
| Polymorphic associations with no FK integrity | **Procedure** | [a polymorphic association](decomposing/a-polymorphic-association.md) — no cop, because the defect is in what the schema cannot say |
| UUID vs bigint decided late | **Uncovered** | — |
| Money as float instead of cents | **Procedure** | [a primitive that should be a type](decomposing/a-primitive-that-should-be-a-type.md). No guard reads column types for meaning, and that stays true |
| Scopes returning arrays, breaking chaining | **Uncovered** | — |
| Reading a replica right after writing primary | **Uncovered** | — |

## Models

| Failure | Verdict | How |
|---|---|---|
| God objects, 800-line `User` | **Guarded** + **Procedure** | `PersistenceHoldsNoBehaviour` fails any public method on a record; [a god record](decomposing/a-god-record.md) |
| Callback chains where order matters | **Unsayable** | `Shipshape/NoCallbacks` |
| Business rules split across validations, callbacks, controllers | **Guarded** | `CallGraph` + `NoDecisionsInRequestHandling` + `PersistenceHoldsNoBehaviour`. The three together leave one place a rule can be |
| `to_s` / `as_json` overridden globally | **Guarded** | Any public method on a record is an offence |
| Model methods hitting external APIs | **Guarded** | `Shipshape/IoIsItsOwnKind` + the call matrix |
| No value objects, primitives everywhere | **Guarded** + **Procedure** | `TypedArguments`, `ShapeIsComposed` — both satisfied by `typed(amount, Float)`, which is the defect declared. [a primitive that should be a type](decomposing/a-primitive-that-should-be-a-type.md) is how you find them |
| Concerns as dumping grounds | **Guarded** + **Procedure** | `MixinsAddNothingPublic`; [a shared concern](decomposing/a-shared-concern.md), [a record concern](decomposing/a-record-concern.md) |
| STI overuse, endless `type` conditionals | **Guarded** + **Procedure** | `NoTypeInterrogation`; [a type hierarchy](decomposing/a-type-hierarchy.md) |
| Delegation chains hiding nil errors | **Guarded on records** | `PersistenceHoldsNoBehaviour` — a gap this survey found, now closed. Elsewhere it stays exempt: `code-is-written-not-generated` draws its line at framework macros and uses `delegate` to draw it |
| `attr_accessor` shadowing a real column | **Uncovered** | — |

## Controllers

| Failure | Verdict | How |
|---|---|---|
| Business logic in actions | **Guarded** + **Procedure** | `NoDecisionsInRequestHandling`; [a fat controller](decomposing/a-fat-controller.md) |
| Ignoring `save`'s return value, silent failures | **Unsayable** | An operation answers a `Result`; `OperationsReportWhatTheyDid`, `NoEmptyRescue` |
| Authorization checked in views instead of controllers | **Unsayable** | `permits?` is one predicate — the view asks it to offer the button, the door asks it to refuse. There is no second answer to get out of step |
| Loose strong params, mass assignment | **Guarded** | `NoInlineParamParse`, `NoUnparsedLookup`, `TypedArguments` |
| Fat `params` juggling instead of form objects | **Guarded** | Parsed at the seam, typed at construction |
| `before_action` chains that make flow untraceable | **Procedure** | [a filter chain](decomposing/a-filter-chain.md). Still uncovered by any cop — the branching is in `only:`/`except:`, which nothing here reads |
| No pagination on index actions | **Uncovered** | — |
| Duplicated logic across formats | **Uncovered** | — |
| Nested resources more than one level deep | **Uncovered** | Routing, not shape |
| Redirect loops from callback-based auth | **Uncovered** | — |

## Views

| Failure | Verdict | How |
|---|---|---|
| Helper methods that query the database | **Guarded** | `CallGraph` — the view kind has no edge to a record |
| Turbo streams broadcasting from models | **Guarded** | `PersistenceHoldsNoBehaviour`, `NoDistantWrites`, `NoCallbacks` |
| Logic in ERB templates | **Guarded** + **Procedure** | A view component holds shapes and nothing else; [a form that fails](decomposing/a-form-that-fails.md) |
| N+1 from partials, `render` in a loop | **Uncovered** | Bullet |
| `html_safe` discipline, global CSS/JS, asset pipeline | **Uncovered** | Not shape questions |

## Background jobs

| Failure | Verdict | How |
|---|---|---|
| Passing AR objects instead of IDs | **Unsayable** | `TypedArguments` refuses a record at construction and `HoldsNoRecords` refuses one in a shape; `call_later` serialises typed arguments |
| Jobs enqueued in `after_save`, before commit | **Unsayable** | There is no `after_save` |
| Jobs that aren't idempotent, then retried | **Guarded** | `Shipshape/CommandsProveIdempotence` — every command's test says what happens on the second run |
| Unbounded retries hammering a broken dependency | **Guarded** | Per-command `ATTEMPTS` on the installed job |
| No failure visibility | **Guarded** | Every operation records to the audit log, failures included |
| Long work in the request cycle | **Uncovered** | `call_later` makes deferring one word; nothing says when you should |
| One queue for everything | **Uncovered** | — |
| **Cron jobs with no locking, two servers running the same task** | **Uncovered, deliberately** | Scheduling has not been decided in this canon. It came up once, a law was drafted unasked, and it was deleted — see below |

## Caching

Every row — stale keys, no expiry, Russian doll without `touch:`, user data under a shared key,
stampede on expiry — is **Uncovered**. Nothing here reads a cache, and no static rule could.

The one structural contribution: reads are named `Query` classes, so a cache has an obvious
place to live and one place to be invalidated from. That is a precondition, not a guard.

## Migrations and deploys

| Failure | Verdict | How |
|---|---|---|
| Adding a column with a default, table lock | **Unsayable** | No column carries a default |
| Everything else — concurrent indexes, renames under old code, data migrations in schema migrations, no rollback, schema drift, migrate-and-deploy together | **Uncovered** | `strong_migrations` is the tool. This is a real and deliberate hole: shipshape reads `db/schema.rb` for what it admits, never migrations for how they run |

## Testing

| Failure | Verdict | How |
|---|---|---|
| Testing implementation instead of behaviour | **Procedure** | [characterise the edges](decomposing/characterise-the-edges.md) — the black-box step before every other step |
| No system tests for critical paths | **Procedure** | `shipshape edges` lists the edges no test names |
| Time-dependent tests without `travel_to` | **Guarded** | `NoAmbientReads` — the clock is an argument, so there is no ambient time to freeze |
| Fixtures with global state, slow factories, over-mocking, `sleep`, no transactional cleanup | **Uncovered** | Suite hygiene. `CommandsProveIdempotence` is the only rule here about what a test must say |

## Security

| Failure | Verdict | How |
|---|---|---|
| Authorization by obscurity, hidden buttons over open routes | **Unsayable** | Every door checks; `EveryDoorChecksPermission` fails a base class that lost the check |
| IDOR, `Model.find(params[:id])` with no ownership scoping | **Partly guarded** | `NoUnparsedLookup` stops the raw param; the permission check has one home. **Ownership itself is the application's rule** |
| Logging params containing passwords or tokens | **Guarded** | `PersonalDataIsDeclared` plus audit-log redaction |
| Secrets in code, missing CSRF, no rate limiting, CVEs, file uploads, `send_file` paths | **Uncovered** | brakeman, `bundler-audit`, `rack-attack`. Named here so nobody reads a green `shipshape check` as a security pass |

## Operations and observability

| Failure | Verdict | How |
|---|---|---|
| Error tracking without context | **Partly guarded** | The audit log carries operation, actor, outcome and error for every operation |
| No timeouts on outbound HTTP | **Uncovered** | `IoIsItsOwnKind` gives the call one place to put a timeout. It does not check that you did |
| Environment drift, no APM, health checks, connection pool, memory bloat, log volume, third-party cascade | **Uncovered** | Every one of these is a running system reporting on itself. Nothing in this canon runs |

## Architecture and process

| Failure | Verdict | How |
|---|---|---|
| **Conventions documented but not enforced in CI** | **This is the whole thesis** | [`one-mechanism-guards-everything`](laws/one-mechanism-guards-everything.md), the canaries, `rake test:removal`, `a-guard-states-its-limit`. A convention nobody enforces is the failure shipshape exists to answer |
| No clear boundary between domain and framework | **Guarded** | `Shipshape/CallGraph` is exactly this, declared once as a matrix |
| Premature service extraction | **Procedure** | [a service](decomposing/a-service.md), and the detangling stance generally |
| Gem sprawl, engines vs modules, stale feature flags, EOL Rails | **Uncovered** | — |

---

## Roughly, the count

Of about 120 rows: **15 unsayable, 28 guarded or partly guarded, 13 held by a procedure, and
about 64 uncovered.**

**Those numbers moved because of this document.** It was written as a survey and turned into a
work list: two gaps became cop clauses, four became procedures, and the counts above are the
second reading, not the first. That is the use of writing coverage down — the first count was
16 uncovered rows worse, and none of them were unknown, only unwritten.

**The 70 is the honest headline and it is not an apology.** Around forty of them are runtime,
volume, or infrastructure questions that a file reader cannot answer and should not claim. What
matters is that they are written down: a green `shipshape check` now means something specific,
and the specific thing it means is not "this application is well".

## What this exercise found

Two gaps that no test would have surfaced, because both are code the canon has an opinion about
and no guard reads:

- **`default_scope` and `unscoped`.** `PersistenceHoldsNoBehaviour` matches `scope` exactly, so
  the one scope that applies to every query — and to `create` — is invisible to it. A rule that
  reaches every read in the application is the strongest form of the thing that law forbids.
- **`delegate`.** It writes public methods onto a record, which is what
  `persistence-holds-no-behaviour` exists to prevent, and it is neither a `def` nor in
  `NoGeneratedInterfaces`'s macro lists. A delegation chain is also the classic way a `nil`
  travels three objects from where it will be blamed.

**Both are now closed, and neither needed a new law** — they were shapes an existing law
already forbade and no clause read. That is the direction to prefer: a cop's clause count
measures how many ways the code can say one thing, and closing a gap by widening a clause
leaves the canon the same size.

**One boundary was left where it was.** `delegate` is banned on records and nowhere else,
because `code-is-written-not-generated` exempts the framework's public conventions on purpose
and uses `delegate` as the example that draws the line. Moving that line is a separate
decision from closing this gap, and it has not been taken.

**And one deliberate blank: scheduling.** Two servers running the same cron with no lock is a
real failure and shipshape says nothing about it. A rule for it was once drafted here without
being asked for, and deleted — a canon that grows by an agent's initiative is not a canon. It
stays open until it is decided.
