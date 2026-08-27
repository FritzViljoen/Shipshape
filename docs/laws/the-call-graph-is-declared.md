# `the-call-graph-is-declared` — Every class has a kind, and which kinds may call which is declared

Every class in the covered trees has a **kind**. The kinds that may call each other are
declared once, as a matrix, in one file. A call whose (caller kind, callee kind) pair is
absent from the matrix is an offence.

The default kinds, and an application may name its own:

| Kind | May call |
|---|---|
| request handling | operation |
| operation | operation, value, record |
| value | value |
| record | nothing |

**This is the load-bearing guard of the canon.** A rule cannot escape its home if there is
nowhere reachable to escape to. It is what stops a call sideways into a sibling area, and a
call upward from a record into an operation, becoming the first instance of a new
convention that nothing yet forbids.

It is also what bounds the second failure of `one-thing-one-place`: a rule everything can
reach becomes the place unrelated things are put.

- **Principle:** `good-boundaries-make-good-neighbours`. `one-thing-one-place` also
  produces it; on conflict the boundary principle governs, because the matrix decides
  reachability and placement follows from it.
- **Guard:** `Shipshape/CallGraph`. Resolves a class's kind by base class first, then by
  path. Fails a call to a constant whose kind is not reachable from the calling file's
  kind. The matrix is data, in one file, and the cop reads it.
- **Guard's limit:** it resolves receivers syntactically. A call through a local assigned
  earlier, through a method that returns a collaborator, through `send`, or through any
  metaprogrammed dispatch, is invisible. A class it cannot assign a kind to is skipped
  rather than failed — and the count of skipped classes is reported, because a silently
  unclassified tree is exactly the coverage-shaped hole this canon warns about.
