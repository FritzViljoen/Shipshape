# `no-silent-coercion` — Nothing turns bad input into a plausible value

An operation completes, or it says why it did not. What it may never do is answer.

**Forbidden:** a cast that cannot fail turning rubbish into a number. A rescue that returns a
default. A rescue with an empty body, or a body that only logs. A lookup that answers nil
where the caller had no way to know a row was required.

**The failure mode is not the unknown error; it is the known error, swallowed.** Yuan et al.
found 92% of catastrophic failures in production distributed systems came from mishandling
errors that had already been signalled, and that a third of those were trivial — an empty
handler, a bare log, a `TODO` (OSDI 2014, cited in [the principles](../principles.md)).

A defect raises. An expected failure the caller can act on comes back as a value, because a
caller forbidden to interrogate can only know what it is told.

- **Principle:** `nothing-fails-quietly`
- **Guard:** `Shipshape/NoSilentCoercion` flags the non-raising numeric and string casts on a
  value traceable to an untrusted source in the same expression.
  `Shipshape/NoEmptyRescue` flags a rescue whose body is empty, is only a log, or only
  returns a literal.

- **Guard's limit:** a cast on a value already asserted as the right type is harmless and
  **syntactically identical** to the forbidden one, so the cop covers only same-expression
  traceable cases and misses every value that passed through a local first. "Only logs" is a
  closed list of logger receivers. A rescue that swallows by returning a computed value
  rather than a literal is invisible, and that is the hardest case, not the rarest.
