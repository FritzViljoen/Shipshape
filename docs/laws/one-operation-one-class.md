# `one-operation-one-class` — An operation is a class with one public method

One class, one operation, one public method named `call`, taking keyword arguments.

A second public method is a second operation, and it gets a second class. No positional
parameters, no `**rest`, no `(...)` — every input is a named keyword, because a collected
parameter is a hole in every other law that inspects the signature.

**It answers the same way as every other operation.** A uniform shape is what lets one
wrapper serve every call site: logging, instrumentation, an audit trail, a migration seam.
Four call conventions and none of those can exist.

**Reading and writing are separate classes**, told apart by their names and by what they
do — never by a flag. A flag deciding which of two things a call does is two operations
wearing one name.

**A new case is a new class.** Not by exhortation: a single-method class has nowhere to
grow a branch, and [`the-call-graph-is-declared`](the-call-graph-is-declared.md) gives the
branch nowhere to reach.

**Size an operation so it can be permitted or refused whole.** This is the sizing test, and
it is the one judgement the rest of the model leans on: when deciding what a command or
query should cover, ask who is allowed to do it. If one actor may do half of what it does
and not the other half, it is two operations, and the seam runs exactly where permission
runs.

Getting this wrong is not a naming problem. An operation that spans two permissions has
nowhere to put the refusal: it either checks halfway through and leaves the first half
done, or it takes the widest permission of the two and quietly grants the narrow one. Both
are found in production, and both are re-sizing work by then.

The reverse is just as wrong — splitting one permitted act into three operations means the
caller sequences them, and a caller that can sequence them can stop after the first. **A
permission boundary is a transaction boundary is an operation boundary**, and where those
three disagree the design is not finished.

This is a judgement and no check makes it. It is written here because the sizing question
has no other home, and an unwritten judgement gets made differently by every reader.

- **Principle:** `one-way-to-say-each-thing`
- **Guard:** `Shipshape/OneOperationOneClass`, over classes of a kind listed in
  `OperationKinds`. Fails a second public method, a public method not named `call`, a
  public `attr_reader`/`attr_accessor`/`attr_writer` — which is a public method in all but
  name — and any parameter that is not a named keyword: positional, optional positional,
  `*rest`, `**rest`, and `(...)`. Each refusal says which it was, because "use keywords"
  without the reason gets worked around rather than fixed.
- **Guard's limit:** it cannot tell whether the one method does one thing. A two-hundred
  line `call` passes. Class and method length are a separate concern and this cop does not
  cover them. It cannot see a public method added at runtime. `initialize` is exempt —
  Ruby makes it private whatever the file says, and this law requires a hand-written one —
  so a constructor doing the work of an operation is invisible here.

  The layout it reads is declared once, on `Shipshape/CallGraph`, and a file of no declared
  kind is left alone rather than judged.
