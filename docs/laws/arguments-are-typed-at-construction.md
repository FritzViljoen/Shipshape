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
- **Guard:** `Shipshape/TypedArguments`. Recognises an operation by what it inherits, not by
  where it is filed, so it stays covered wherever it is put. Every keyword must reach a
  guard call. Anything that is not a named keyword is its own offence — `**rest`, `(...)`, a
  positional parameter, a positional Hash default — because a keyword-less initializer
  silently accepts the caller's keywords as one Hash and the call succeeds.
  **Not built yet** — so this is a convention today, held by review. The law is
  written anyway: a rule nobody wrote down cannot be built later.

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
