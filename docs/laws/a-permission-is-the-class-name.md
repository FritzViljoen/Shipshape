# `a-permission-is-the-class-name` — The operation's class name is the permission

`SettleInvoice` needs `:SettleInvoice`. Not a transform of the name: every transform is lossy
and a lossy transform collides — `FooBar` and `Foo::Bar` both underscore to `:foo_bar`, so a
grant issued for one runs the other. A `PERMISSION` constant beside the class is a second name
for one thing, and two names that can diverge do.

Uniqueness is free: two classes cannot share a constant, so no guard has to check it.

## It fails closed

A new write's permission exists the moment the class does, and nobody holds it. There is no
constant to forget, so requiring nothing cannot happen by omission — the way an omitted
declaration fails open.

**An operation that runs before anyone is identified implements `anonymous_call`.** The base
class asks `instance_methods(false)` — **this class only, never an ancestor or a module.**
`method_defined?` searches both, and a concern defining `anonymous_call` then made every write
that included it public. That makes publicness a property of the class, never of the caller: there is no `public_call` for a caller
to reach for. `grep -rn "def anonymous_call"` is the whole set, and it should only shrink. An
actor who is known but needs no grant is a different case — give it an ordinary permission
granted to everyone, so it stays revocable.

**A nil actor raises.** A nil taken to mean "public" is the fail-open this law exists to
prevent.

## An operation demands what it reaches

A workflow calling its steps and a write calling a read are the same sentence. There is one
rule, and no lighter case for writes — the version of this law that had one lasted a day.

Each door already checked on its own way in, so an inner read refused mid-write raised
*there*: a 500 after the outer check passed, where
[`an-operation-answers-a-result`](an-operation-answers-a-result.md) promises an outcome.
Aggregating moves the refusal to the door.

**There is no third answer** for an actor short of an inner permission: grant it, or make the
inner operation `anonymous_call`, which is how a read declares it needs no grant of its own. A
read reachable from a controller implements `call` and is granted; one that is part of its
caller's act does not.

**Anonymity is closed downward.** An anonymous operation may not reach a guarded one, or the
declaration launders everything beneath it. What it *does* reach aggregates upward into a
guarded caller, so nothing is lost by passing through one.

The cost, stated: a write that gains an internal read gains a permission, so an internal
refactor can become an authorisation change. `CallGraph.routes` is what makes that survivable —
the grants each endpoint demands are derived, not remembered.

## A workflow contributes no name

Granting `:SettleMonth` does nothing: a workflow performs no act, only sequences ones that do.
And it refuses before the first step, because it spans transactions and cannot take one back —
for a write the aggregate buys a tidier refusal, for a workflow the only moment refusing is
free.

## Permission is code; capability is data

| | what it is | where it lives | how many |
|---|---|---|---|
| Permission | what the code requires | the class name, derived | one per operation |
| Capability | what an administrator grants | a row | a couple of dozen |
| The join | which permissions a capability contains | rows | authored once |

`actor.may?` resolves through the join. **`may?` is the application's method** — shipshape
never sees capabilities. Existing grants do not move; what is new is the join.

The catalogue is derived, so nothing can fall behind the code:

```ruby
CallGraph.grantable(Write, Read)   # everything an actor can be asked for
CallGraph.unchecked(Write, Read)   # declared to need no grant
CallGraph.routes                      # per endpoint, which is the question being asked
CallGraph.leaks(Write, Read)       # anonymity that is not closed downward
```

**The keys are class names**, which is what a label table is keyed by. "Cancel a booking" is
content, and belongs in a row.

- **Principle:** `one-way-to-say-each-thing` governs — one thing, one name.
  `make-the-wrong-thing-impossible` produces the base-class placement.
- **Guard:** the generated `permission.rb`, `calls.rb` and `call_graph.rb` — architecture. The
  permission IS `name.to_sym`; `Permission#permissions` aggregates what an operation reaches
  and the door's private `permits?` demands all of it; `Calls` reads the syntax tree once for
  both a workflow's steps and a graph edge. Exercised by `generated_base_classes_test.rb`.
- **Guard:** `Shipshape/EveryDoorChecksPermission` holds what the base classes cannot hold
  themselves — `install` never overwrites, so a door that lost its check would disable
  authorisation for its whole kind with nothing else failing.
- **Guard:** `Shipshape/AggregationIsReadable`, over every operation kind. What an operation
  reaches is read out of `call`, so this fails what cannot be read there: a receiver that is not
  a constant, an operation reached from another method, and a workflow whose `call` names
  nothing.
- **Guard:** `Shipshape/AnonymityIsClosedDownward`. Fails an `anonymous_call` naming a guarded
  operation.
- **Guard's limit:** **`anonymous_call` is a decision nothing second-guesses.** A read that
  should have been granted, declared anonymous and reaching nothing, is unguarded and looks
  correct. The audit is the grep, and nothing counts them for you.

  `Calls` is **syntactic**: a class reached through a variable, `const_get` or `send` is not an
  edge, so the aggregate and the endpoint row are a floor, not a ceiling. An action whose work
  is in a `before_action` is invisible for the same reason
  [a filter chain](../decomposing/a-filter-chain.md) names. `routes` answers nothing without a
  `Rails.application`, and skips a route whose controller will not load.
- **Guard's limit:** the base class cannot tell whether the actor it was handed is the real
  one, and nothing checks that request handling passes the requester rather than a system
  actor. `EveryDoorChecksPermission` looks for the **call**, not for what it does: a `permits?`
  redefined to answer true passes, and so does one whose result is discarded.
