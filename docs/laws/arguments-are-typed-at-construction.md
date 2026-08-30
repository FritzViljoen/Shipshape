# `arguments-are-typed-at-construction` — Every argument is asserted where it arrives, and nowhere else

An operation takes its arguments in a **hand-written** initializer and passes every keyword
through a type guard. The guard **asserts and never coerces**; a mismatch raises, because it
is the caller's defect and not an answer anybody is waiting for.

**The boundary is the point.** Past that line nothing re-checks, and a failure has a side:
at the guard it is the caller's defect, after it the operation's own. Re-checking inside is
not caution, it is a second place deciding the same thing.

**The initializer is written, not generated.** A macro declaring the inputs and building the
initializer behind them would hide both the assignment and the assertion, and `typed(on,
Date)` would stop being greppable — see
[`code-is-written-not-generated`](code-is-written-not-generated.md).

- **Principle:** `nothing-crosses-unasserted`. `nothing-is-hidden` produces the
  written-not-generated half; on conflict `nothing-crosses-unasserted` governs.
**A record is never an argument.** Not into a command, not into a shape, not into anything.
A record that travels carries the database with it, and whatever receives it can walk an
association, write through it, and reopen a query where nobody is looking for one — with
`@person.orders` and no constant for the call graph to see. What a receiver needs is the
fields, a shape built from them, or the id to load for itself.

The generated `typed` refuses one, which covers every kind at once because every base class
includes `TypedArguments`, and refuses it **before** the type is matched: declaring
`typed(person, PersonRecord)` is not a licence, it is the clearest statement of the defect.

That leaves the class that never calls `typed`. So the presentation kinds — `Shape` and the
generated `ApplicationViewComponent` — also sweep what they ended up holding, through
`HoldsNoRecords`. Two moments, one rule: `typed` names the keyword and is the better message;
the sweep cannot be skipped and is the better guarantee. Each was watched to fail with the
other in place, which is what says they are not one guard written twice.

- **Guard:** the generated `typed_arguments.rb` — architecture. `typed` asserts and never
  coerces, and refuses a record before it matches the type.
- **Guard:** `Shipshape/TypedArguments`. Within a governed tree the **superclass decides
  the kind**, so an operation stays covered wherever it is filed inside one. Every keyword
  must reach a
  guard call. Anything that is not a named keyword is its own offence — `**rest`, `(...)`, a
  positional parameter, a positional Hash default — because a keyword-less initializer
  silently accepts the caller's keywords as one Hash and the call succeeds.

**`Boolean` is a name, not a class.** Ruby has none, and the usual workaround — reopening
`TrueClass` and `FalseClass` to include a marker module — changes two objects nobody owns,
from a library, invisibly. That is the defect
[`nothing-travels-off-the-call-path`](nothing-travels-off-the-call-path.md) names, so the
guard knows the name by identity instead and includes it nowhere. `nil` is not false and a
truthy value is not true: absence says so with `allow_nil:`, and anything else would be a
coercion.

- **Guard's limit:** it checks that a keyword **is** guarded, never that the type named is
  the right one. `typed(person, Date)` passes. It also cannot see a guard called through a
  helper it does not know by name.

  **An operation with no initializer at all is invisible**, because the cop hangs off
  `def initialize` and there is nothing to hang off. Found by running this over a repository
  whose operations declare their inputs with an attribute macro: 24 of 24 had no
  initializer, and the cop reported clean over the exact shape this law was written against.
  A macro declaring the inputs is
  [`code-is-written-not-generated`](code-is-written-not-generated.md)'s business, and its
  cop only knows the constructs it names — a house DSL is not one of them.

  **A tree nobody declared is not inspected at all.** An operation in `app/services/` — the
  usual home of exactly the untyped operations this law is for — is silent until that path
  is added to the layout. The superclass decides the kind; the globs decide whether the file
  is looked at, and a file outside every glob is left alone rather than judged.
