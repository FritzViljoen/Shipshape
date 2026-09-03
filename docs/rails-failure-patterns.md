# What shipshape covers, and what it does not

A survey, not a law. It works through the ways Rails applications fail — around 120 of them,
gathered without reference to this canon so the answers could not be arranged to flatter it —
and asks of each **which ones a guard here actually holds**.

Its companion, [the patterns people reach for](rails-patterns.md), takes the same subject from
the other end: what teams adopt to stop these failures, and what this canon does instead.

The short answer: **it holds roughly half, and the half it holds is one half on purpose.**

---

## The dividing line is shape against runtime

**shipshape governs where code lives and what form it takes.** It reads files. It can tell you
that a rule is in a controller, that a record has a method, that a migration adds a nullable
column, that a module adds public surface. It cannot tell you that a page issued 400 queries, that a cache key
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
| Missing `NOT NULL` on columns that require a value | **Guarded** | `Shipshape/NoNullableColumns`, over `db/migrate/**` — **the migrations, not the live schema**, and with an exemption for the `*_from_*` renames. A column that was nullable before this gem arrived is not caught; a new one is |
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
| Missing indexes on foreign keys | **Procedure** | [an unindexed foreign key](decomposing/an-unindexed-foreign-key.md) — a runtime failure with a structural cause: both facts are in `db/schema.rb`, which this canon already reads |
| Missing indexes on sort and uniqueness columns | **Uncovered** | `lol_dba`. Which column a query sorts on is not in the schema |
| `dependent: :destroy` on huge associations | **Uncovered** | And note the tension: `AssociationsSurviveErasure` *demands* a `dependent:`, for erasure, which can make this worse |
| Enum as array, reordering silently remaps rows | **Procedure** | [an enum as an array](decomposing/an-enum-as-an-array.md). `no-nullable-columns` misses it: `0` is the first value *and* the empty integer, so the column need not be nullable to lose the distinction |
| `find_each` ignored, `.all.each` loads the world | **Procedure** | [an unbounded read](decomposing/an-unbounded-read.md) |
| Counter drift: manual counters fighting `counter_cache` | **Procedure** | [a stored derivation](decomposing/a-stored-derivation.md). A counter is a cache; it is sanctioned as a last resort, named `*_cache_record`, and only where its invalidation is written down |
| `pluck` vs `select` | **Uncovered** | Runtime and volume, not shape |
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
| Authorization checked in views instead of controllers | **Unsayable** | There is no predicate for a view to ask: `permits?` is private to the door. A page offers the action and places the refusal, or a query hands it a shape that already says what is offerable |
| Loose strong params, mass assignment | **Guarded** | `NoInlineParamParse`, `NoUnparsedLookup`, `TypedArguments` |
| Fat `params` juggling instead of form objects | **Guarded** | Parsed at the seam, typed at construction |
| `before_action` chains that make flow untraceable | **Procedure** | [a filter chain](decomposing/a-filter-chain.md). Still uncovered by any cop — the branching is in `only:`/`except:`, which nothing here reads |
| No pagination on index actions | **Procedure** | [an unbounded read](decomposing/an-unbounded-read.md) — size is a runtime fact, so the bound is made an argument instead |
| Duplicated logic across formats | **Uncovered** | — |
| Nested resources more than one level deep | **Uncovered** | Routing, not shape |
| Redirect loops from callback-based auth | **Uncovered** | — |

## Views

| Failure | Verdict | How |
|---|---|---|
| Helper methods that query the database | **Partly guarded** | `CallGraph` gives the view kind no edge to a record. **`app/helpers` resolves to no kind at all** — the layout has no helper kind, deliberately, because helpers dissolve — so a helper is inspected by nothing until its code moves |
| Turbo streams broadcasting from models | **Guarded** | `PersistenceHoldsNoBehaviour`, `NoDistantWrites`, `NoCallbacks` |
| Work that happens because something was saved | **Guarded** + **Procedure** | `NoCallbacks`; [a callback web](decomposing/a-callback-web.md). A consequence becomes a named step in a workflow — there is no "also", and a trigger table is a callback with a table in front of it |
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
| Long work in the request cycle | **Procedure** | [work in the request cycle](decomposing/work-in-the-request-cycle.md). `call_later` makes the mechanics one word, which is why the procedure is all judgement |
| One queue for everything | **Uncovered** | — |
| Cron jobs with no locking, two servers running the same task | **Guarded** | `Shipshape/NothingSchedulesWork` and [`a-schedule-is-a-row`](laws/a-schedule-is-a-row.md). A schedule is a stored request naming a route and an actor; two servers firing one row is a double-post, which `a-command-runs-twice` already obliges every command to survive |

## Caching

Every row — stale keys, no expiry, Russian doll without `touch:`, user data under a shared key,
stampede on expiry — is **Uncovered**. Nothing here reads a cache, and no static rule could.

**One thing next door is covered.** A cache *in the database* — a saved query answer in its own
table — is sanctioned as a last resort by [a stored derivation](decomposing/a-stored-derivation.md),
under a name that makes it greppable and a gate that refuses it unless the invalidation is
written down. That is not fragment caching and does not help with any row above it.

The one structural contribution: reads are named `Query` classes, so a cache has an obvious
place to live and one place to be invalidated from. That is a precondition, not a guard.

## Migrations and deploys

| Failure | Verdict | How |
|---|---|---|
| Adding a column with a default, table lock | **Unsayable** | No column carries a default |
| Everything else — concurrent indexes, renames under old code, data migrations in schema migrations, no rollback, schema drift, migrate-and-deploy together | **Uncovered** | `strong_migrations` is the tool. shipshape reads migrations for **what they declare** — a nullable column, a default — and never for how they run |

## Testing

| Failure | Verdict | How |
|---|---|---|
| Testing implementation instead of behaviour | **Procedure** | [characterise the edges](decomposing/characterise-the-edges.md) — the black-box step before every other step |
| No system tests for critical paths | **Procedure** | `shipshape edges` lists the edges no test names |
| Time-dependent tests without `travel_to` | **Unsayable in the operation, uncovered in the test** | `NoAmbientReads` makes the clock an argument, so an operation has no ambient time to freeze. The cop is kind-scoped and no test path resolves to a kind, so nothing reads the test itself |
| Tests coupled to fixtures and factories with implicit global state | **Guarded** + **Procedure** | `Shipshape/NoTestFactories` and [`no-test-factories`](laws/no-test-factories.md); [a factory graph](decomposing/a-factory-graph.md). A test builds state by calling operations, because a factory can build a row the application cannot |
| Factories that build entire object graphs, slow suite | **Procedure** | [a factory graph](decomposing/a-factory-graph.md) |
| Over-mocking, `sleep`, no transactional cleanup | **Uncovered** | Suite hygiene the canon does not reach |

## Security

| Failure | Verdict | How |
|---|---|---|
| Authorization by obscurity, hidden buttons over open routes | **Unsayable** | Every door checks; `EveryDoorChecksPermission` fails a base class that lost the check |
| IDOR, `Model.find(params[:id])` with no ownership scoping | **Procedure** | [an unowned find](decomposing/an-unowned-find.md). `NoUnparsedLookup` stops the raw param, but a permission **is a class name** — it says which actor may update stories, never which stories, and it never can. Row-level ownership is deliberately outside the model |
| Logging params containing passwords or tokens | **Guarded** | `PersonalDataIsDeclared` plus audit-log redaction |
| Secrets in code, missing CSRF, no rate limiting, CVEs, file uploads, `send_file` paths | **Uncovered** | brakeman, `bundler-audit`, `rack-attack`. Named here so nobody reads a green `shipshape check` as a security pass |

## Operations and observability

| Failure | Verdict | How |
|---|---|---|
| Error tracking without context | **Partly guarded** | The audit log carries operation, actor, outcome and error for every operation |
| No timeouts on outbound HTTP | **Procedure** | [an untimed call](decomposing/an-untimed-call.md). `IoIsItsOwnKind` gives the call one place to put a timeout; it does not check that you did |
| Third-party outage cascading into downtime | **Partly procedure** | [an untimed call](decomposing/an-untimed-call.md) bounds the wait. A bound is not a circuit breaker, and this canon has no answer for that |
| Environment drift, no APM, health checks, connection pool, memory bloat, log volume | **Uncovered** | Every one of these is a running system reporting on itself. Nothing in this canon runs |

## Architecture and process

| Failure | Verdict | How |
|---|---|---|
| **Conventions documented but not enforced in CI** | **This is the whole thesis** | [`one-mechanism-guards-everything`](laws/one-mechanism-guards-everything.md), the canaries, `rake test:removal`, `a-guard-states-its-limit`. A convention nobody enforces is the failure shipshape exists to answer |
| No clear boundary between domain and framework | **Guarded** | `Shipshape/CallGraph` is exactly this, declared once as a matrix |
| Premature service extraction | **Procedure** | [a service](decomposing/a-service.md), and the detangling stance generally |
| Feature flags added but never removed | **Procedure** | [a feature flag](decomposing/a-feature-flag.md). No cop reads a calendar, and what makes a flag a defect is time |
| Gem sprawl, engines vs modules, EOL Rails | **Uncovered** | — |

---

## Counting it

Count the verdict column yourself — every row carries one, and a number written here would be a
copy of a fact this document already holds. It drifted once already, within a day of being
written, which is the whole argument:

```sh
grep '^|' docs/rails-failure-patterns.md \
  | grep -oE '\*\*(Unsayable|Guarded|Partly guarded|Procedure|Partly procedure|Uncovered)\*\*' \
  | sort | uniq -c | sort -rn
```

**What is uncovered is not an apology.** Most of it is runtime, volume or infrastructure —
questions a file reader cannot answer and should not claim. What matters is that those rows are
written down, so a green `shipshape check` means something specific, and the specific thing it
means is not "this application is well".

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

**The one deliberate blank is now decided.** Scheduling was left open here — a rule for it had
been drafted without being asked for, and deleted, because a canon that grows by an agent's
initiative is not a canon. It was then decided on its merits:
[`a-schedule-is-a-row`](laws/a-schedule-is-a-row.md), a stored request that names a route and
the actor it runs as, with [a cadence in code](decomposing/a-cadence-in-code.md) to move an
existing `schedule.rb` onto it. **The host crontabs stay uncovered**, and they are the worst
ones — a `rails runner` line has no actor, no audit entry and no permission check, and nothing
in a repository can see it.
