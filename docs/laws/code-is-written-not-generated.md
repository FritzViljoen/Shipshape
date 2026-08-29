# `code-is-written-not-generated` — No private macro writes code a reader would otherwise grep for

An ordinary initializer, a visible assignment, a greppable type. No macro that declares the
inputs and builds the constructor behind them; no method defined at load time from a list;
no missing-method dispatch standing in for methods that were never written.

**The distinction that makes this workable is public versus private convention.** The
framework's own conventions are exempt, and deliberately so: they have a large public
corpus, and any reader — person or agent — arrives already knowing what they mean. A
convention invented here has a corpus of one repository, so it has to be re-derived from
source on every read, by every reader, and it is re-derived wrong sometimes.

So this law does not forbid metaprogramming. It forbids **your** metaprogramming.

Generation compresses the writing and expands the reading. That was a good trade when
writing was the expensive half; the cost is now paid on every read, forever, by readers who
are not the writer.

- **Principle:** `nothing-is-hidden`
- **Guard:** `Shipshape/NoGeneratedInterfaces`, over the operation, shape and record trees.
  Fails defining methods from data, evaluating a string as code, and missing-method
  dispatch.

- **Guard's limit:** it names **constructs, not intent**. A helper in a gem doing the same
  thing on your behalf is invisible; so is anything generated at build time and committed,
  which reads as ordinary code because by then it is. It cannot judge whether a given macro
  is a public convention or a private one — the tree scoping is what draws that line, and
  the scoping is a judgement nobody checks.
