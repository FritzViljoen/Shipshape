# An adoption order — the sequence that never trades one count for another

A procedure, meant to be followed by an agent one step at a time. Every step ends with
something to **run**, because a decomposition nobody can verify is a rewrite with extra
confidence.

**What you are aiming at:** every guard on, with a floor that only falls — reached in an order
where **no step trades one count for another.** Turning everything on at once produces a number
nobody can act on and a build nobody can go green on; the sequence below exists so that each
step leaves the repository better by a measure you can name, and none of them undoes an earlier
one.

**Start here**, before any other procedure. The rest of this playbook takes one shape apart;
this one gets the guards onto a repository that already runs, in an order that does not fight
them.

---

## Why order matters at all, and where it does not

**The cops have no order and need none.** RuboCop runs every one over each file in a single
pass, and no cop here reads another's output — the cross-file ones read files from disk. There
is nothing to sequence.

**The ratchet is what has an opinion.** `shipshape check` compares each cop's count against the
merge-base and fails where one **rose**, cop by cop. That is deliberate: a total would let a new
violation hide behind a fixed one. The cost is that work which *moves* an offence from one cop
to another reads as a regression — take a rule off a record before the question tree is declared,
and `PersistenceHoldsNoBehaviour` falls while `CallGraph` climbs.

**The unit is the branch, not the commit.** The baseline is the merge-base, so a trade that
balances anywhere on the branch nets to nothing. Order matters for the work you can finish, not
for how you slice the commits.

---

## 0. Install with authorisation off

```sh
bundle exec shipshape install
```

Authorisation is opt-in and off by default, because base classes demanding an actor on day one
would stop every call site at once — which is not a migration, it is an outage.

**Check:** the application still boots, and `app/shipshape/` holds the base classes.

---

## 1. Declare the layout before believing any number

```sh
bundle exec shipshape coverage
```

Until a tree is named in `Shipshape/CallGraph`'s `Kinds`, every kind-scoped cop skips it —
silently, and indistinguishably from approving of it. **A clean run means nothing until this
number is one you recognise.**

**Check:** `coverage` reports a percentage you can explain, and the kinds you expect appear in
the breakdown. A kind missing from the list matched nothing, whatever its globs say.

**`Kinds` is not the only thing to declare here — `BaseClasses` is.** The shipped
`entry_point` row covers `app/jobs/`, `app/subscribers/` and `app/channels/` together, but
its `BaseClasses` entry ships only a job base and a channel base — no subscriber base, because
`shipshape install` writes none. A subscriber inheriting nothing is a real gap
`Shipshape/KindIsInheritedNotOnlyPlaced` correctly reports; a subscriber inheriting its own
`ApplicationSubscriber` reports one too until that class is added to `entry_point`'s
`BaseClasses`. Add it — or any other kind's own base an application rolls itself and does not
find here — in this same step, before believing that cop's number either.

---

## 2. Turn the ratchet on, and stop reading the absolute count

```sh
bundle exec shipshape check
```

From here the inherited pile is not your bill; a rise is. **Enabling a cop is free** — both
trees are measured with the head configuration, so switching one on finds its offences in the
baseline too and none of them count as new.

**Three cops start off, and it is not a concession.** A cop is off while obeying it would
require something that does not exist yet. Add all three to the repository's own
`.rubocop.yml`:

```yaml
Shipshape/NoTestFactories:
  Enabled: false

Shipshape/NoTestMixins:
  Enabled: false

Shipshape/NoDecisionsInRequestHandling:
  Enabled: false
```

| cop | off until | because |
|---|---|---|
| `Shipshape/NoTestFactories` | the tests step | a test builds state by calling operations, and until the operations step there are none to call |
| `Shipshape/NoTestMixins` | the tests step | a legacy suite shares setup through ad hoc modules the same way it shares state through factories, and turning this on before those are swept onto the base class makes every characterisation test's first touch a two-law fix |
| `Shipshape/NoDecisionsInRequestHandling` | the operations step | an action places what an operation answered, and until then there is nothing answering |

**`Shipshape/BaseTestClassGrowth` is not on this list, on purpose.** It fires only when a base
or support class is itself edited — never on an ordinary leaf test — and the one thing it
demands, growing the base class instead of a mixin, is the sanctioned alternative `NoTestMixins`
already points at. Turning it off would remove the one guard against the first shared-setup
addition ballooning, for a cop that does not penalise writing a test at all.

**Check:** `check` names all three as `OFF` on every run, so the disclosure travels with the
report rather than living only in `.rubocop.yml`.

**The test for the list is not volume.** `Shipshape/PersistenceHoldsNoBehaviour` reports 351 on
lobsters and stays on, because a large inherited count is exactly what the ratchet is for. What
earns a place here is a cop that **penalises the work you are doing to satisfy it** — one that
fires when you write a test, or when you write an action. Those two block adoption; a big number
does not.

**The list only shrinks.** Turning one on is free at any point, because both trees are measured
with the head configuration. Adding a third is a decision somebody has to see in a diff.

**Check:** `check` runs and reports a baseline sha. If the application's own `.rubocop.yml`
cannot be loaded beside RuboCop 1.x, use `--config` with a file at the repository root — a
config in a subdirectory resolves its globs against that directory and silences every
kind-scoped cop.

---

## 3. Characterise the edges

[Characterising the edges](characterise-the-edges.md), in full. Every procedure after this
moves internals; the edge test is the only thing that will notice if behaviour changed.

**Check:** `shipshape edges` lists what no test names, and the list is shorter than it was.

---

## 4. Records before the operations that will use them

[A god record](a-god-record.md), [a callback web](a-callback-web.md), and the `default_scope`
and `delegate` clauses of `persistence-holds-no-behaviour`.

**This is first because everything else lands on top of it.** An action decomposed while its
rules still live on the record produces a deed that wraps the same god object — the
extraction moved a call site and nothing else. [A fat controller](a-fat-controller.md) says so
in its own step 0, and this is the same advice at repository scale.

**Check:** `Shipshape/PersistenceHoldsNoBehaviour` and `NoCallbacks` have fallen, and nothing
else rose.

---

## 5. Parse at the seam before moving any find

`Shipshape/NoInlineParamParse` first, then `NoUnparsedLookup`.

**The order is load-bearing.** Move a find into an operation while the parameter is still raw
and the raw parameter travels with it — `NoUnparsedLookup` climbs by exactly the number of
finds you moved. Parsed first, the same move is silent.

**Check:** `NoInlineParamParse` is silent before a single find moves.

---

## 6. Audit the permissions that already exist

[An authorisation audit](an-authorisation-audit.md), in full.

**Knowing the authorisation model and enforcing it are different acts.** The operations step
that follows sizes each new class by
[`a-permission-is-the-class-name`](../laws/a-permission-is-the-class-name.md) — one grant, one
act, one class — and that fact already exists in the application today, in whatever CanCan,
Pundit or ad-hoc role check enforces it now. Reading it changes nothing, so it can happen here,
before a single operation is written. Enforcing it stays last, for the reason given there: a
base class demanding an actor on day one stops every call site at once.

Skip this step and the operations step has only the schema for a signal — which is how a real
migration produced hundreds of small CRUD-shaped deeds, one per table, with authorisation
not even considered until three steps later.

**Check:** every controller action in `bin/rails routes` has a row in the audit's table — gated
by a named permission, or marked ungated for a person to answer.

---

## 7. Then the operations, sized by the audit

[A fat controller](a-fat-controller.md), [a service](a-service.md), [a scope
chain](a-scope-chain.md), [a filter chain](a-filter-chain.md).

This is where the count falls fastest, and it is safe now: the rules are off the records, the
seam parses, and the edges are recorded. **The operations to build are the permissions the
previous step found, minimised — not the tables that exist.** A controller sitting on four
tables and one permission is one deed; a table reached by three permissions is three.

**Check:** `shipshape next` offers files with tests first, and `check` shows the fall. Every new
deed or question's class name is a permission from the audit's table, not a table name.

---

## 8. The schema, which trades with nothing

[A nullable column](a-nullable-column.md), [an unindexed foreign
key](an-unindexed-foreign-key.md), [an enum as an array](an-enum-as-an-array.md), [a serialized
column](a-serialized-column.md).

These read `db/` and no operation cop reads what they write, so they can be done at any point.
They are here because they are slow, and because a migration that fails is easier to reason
about when the application above it has stopped moving.

**Check:** `AbsenceIsAbsenceNeverAValue` and `NoColumnDefaults` fall; nothing in `app/` moves.

---

## 9. Tests, once there is something to build state with

[A factory graph](a-factory-graph.md) — needs `shipshape install --auth`, run first. `test_call`
is declared inside each template's `auth` branch, so without it there is no second entry point
for that procedure's examples to call. Step 10 is where `--auth` is installed; run that part of
it now, out of order, then come back.

**Last, necessarily.** `no-test-factories` asks a test to build state by calling operations, and
until the operations step there are none to call. Attempting it earlier is how a suite ends up with
a helper wrapping `create!`, which the cop cannot see and which restores exactly what was
removed.

**Check:** `Shipshape/NoTestFactories` falls. Do **not** grep for `create!` and expect nothing:
a record written directly in a test is the honest spelling and this law leaves it alone. What to
look for instead is a shared helper that wraps one — that is a factory with a different name, it
blesses what it builds, and no cop can see it:

```sh
grep -rn "def .*_for_test\|def make_\|def a_valid_" test spec
```

**`Shipshape/NoTestMixins` turns on here too**, once the same sweep has moved a suite's shared
`include`/`extend` modules onto the base class `shipshape install` wrote in step 0. It is the
same migration the grep above is already looking for: a module a test mixes in to share setup is
this law's target exactly as a helper wrapping `create!` is `no-test-factories`'s.

---

## 10. Authorisation, last of all

```sh
bundle exec shipshape install --auth
```

A rollout rather than a decomposition: nothing moves, a check is added. It needs the operations
to exist, which is why it is here and not at step 0 — and `EveryDoorChecksPermission` and
`AnonymityIsClosedDownward` report zero until it has been run, so neither is protecting
anything before this line.

Then seed the permissions from the graph rather than by hand:

```ruby
CallGraph.routes        # what each endpoint demands
CallGraph.grantable(Deed, Question)
CallGraph.leaks(Deed, Question)   # anonymity that is not closed downward
```

**Check:** `leaks` is empty, and an actor holding nothing is refused at every door.

---

## What this leaves you

**A repository where a green run means something.** The layout is declared so the cops reach
the code, the ratchet holds the line from the day it was switched on, and the order above is
the one in which each step's output is the next step's input.

## What none of this proves

**Nothing here says the work is worth doing on this repository.** The order is right; whether to
start is a judgement about the code's remaining life, and a codebase being replaced next year
should be left alone.

**And the order is a default, not a dependency graph.** Steps 4 through 9 genuinely constrain
each other; the schema step constrains nothing and is placed by taste. If a particular
repository's worst pain is in the operations step, the honest answer is often to do one file of
it early, prove the shape to the team, and come back to the order afterwards.
