# `an-operation-call-is-its-own-statement` — One call, one line, one name for what came back

`CreateOrder.call(composition: FindOrderComposition.call(cart_id: cart_id))` runs two
operations in one statement. Written that way it reads as one step, and the reader has to
count constants to find out it is two.

**The failure is attributed to the wrong call.** When the inner operation raises, the
backtrace names the line, and the line is named after the outer operation — so the call that
actually failed is the one nobody can see. The same line says nothing about which of the two
answered `nil`, which is the commonest way this shape is met.

**Naming the intermediate value says what it is.** `composition = …` tells a reader of the
seam what travelled between the two operations; an argument list only says which keyword it
arrived under. That name is the whole documentation of a seam, and nesting deletes it.

**Depth is not the test.** One level of nesting is already the defect, because the failure it
hides is already there. This is a constraint on *how* a permitted call is written, not on
whether it is permitted — [`the-call-graph-is-declared`](the-call-graph-is-declared.md) settles
that separately, and a nested call that the matrix already refuses is two offences, each about
a different thing.

```ruby
# two operations, one statement, one name for both
CreateOrder.call(composition: FindOrderComposition.call(cart_id: cart_id))

# each call is its own statement, and each answer has a name
composition = FindOrderComposition.call(cart_id: cart_id)

CreateOrder.call(composition: composition)
```

- **Principle:** `nothing-is-hidden` governs — the second operation is run by a line that does
  not appear to run it, and the measure is whether a reader can tell what a call does without
  opening it. `nothing-fails-quietly` produces the attribution half: an outcome the caller is
  entitled to act on arrives on a line that names something else.
- **Guard:** `Shipshape/NoNestedOperationCalls`, over `request_handling`, `entry_point`,
  `workflow`, `command`, `query`, `io_command`, `io_query` and both legacy doors. Fails a
  `Const.call` or `Const.call_later` appearing anywhere inside the arguments of another one,
  and reports the **inner** call, which is the one to lift out. A three-deep chain names each
  inner call once rather than once per level.
- **Guard's limit:** it reads `Const.call` on both sides, which is how every operation in this
  canon is invoked — so a callable reached through a local (`builder.call(…)`) is not an
  operation and is not flagged, and neither is an operation nested inside anything that is not
  itself an operation call: `render json: FindOrder.call(id: 1)` passes, deliberately, because
  the outer thing is a response and not a step. It also cannot see the same two calls chained
  rather than nested (`FindOrder.call(…).total`), and a `view_component` is out of scope
  because its whole matrix row is `shape` — a call from one is `Shipshape/CallGraph`'s offence
  before it is this one's.
