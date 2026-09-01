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
to another reads as a regression — take a rule off a record before the query tree is declared,
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

---

## 2. Turn the ratchet on, and stop reading the absolute count

```sh
bundle exec shipshape check
```

From here the inherited pile is not your bill; a rise is. **Enabling a cop is free** — both
trees are measured with the head configuration, so switching one on finds its offences in the
baseline too and none of them count as new.

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
rules still live on the record produces a command that wraps the same god object — the
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

## 6. Then the operations

[A fat controller](a-fat-controller.md), [a service](a-service.md), [a scope
chain](a-scope-chain.md), [a filter chain](a-filter-chain.md).

This is where the count falls fastest, and it is safe now: the rules are off the records, the
seam parses, and the edges are recorded.

**Check:** `shipshape next` offers files with tests first, and `check` shows the fall.

---

## 7. The schema, which trades with nothing

[A nullable column](a-nullable-column.md), [an unindexed foreign
key](an-unindexed-foreign-key.md), [an enum as an array](an-enum-as-an-array.md), [a serialized
column](a-serialized-column.md).

These read `db/` and no operation cop reads what they write, so they can be done at any point.
They are here because they are slow, and because a migration that fails is easier to reason
about when the application above it has stopped moving.

**Check:** `NoNullableColumns` and `NoColumnDefaults` fall; nothing in `app/` moves.

---

## 8. Tests, once there is something to build state with

[A factory graph](a-factory-graph.md).

**Last, necessarily.** `no-test-factories` asks a test to build state by calling operations, and
until step 6 there are no operations to call. Attempting it earlier is how a suite ends up with
a helper wrapping `create!`, which the cop cannot see and which restores exactly what was
removed.

**Check:** `Shipshape/NoTestFactories` falls. Do **not** grep for `create!` and expect nothing:
a record written directly in a test is the honest spelling and this law leaves it alone. What to
look for instead is a shared helper that wraps one — that is a factory with a different name, it
blesses what it builds, and no cop can see it:

```sh
grep -rn "def .*_for_test\|def make_\|def a_valid_" test spec
```

---

## 9. Authorisation, last of all

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
CallGraph.grantable(Command, Query)
CallGraph.leaks(Command, Query)   # anonymity that is not closed downward
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

**And the order is a default, not a dependency graph.** Steps 4 through 8 genuinely constrain
each other; step 7 constrains nothing and is placed by taste. If a particular repository's worst
pain is in step 6, the honest answer is often to do one file of it early, prove the shape to the
team, and come back to the order afterwards.
