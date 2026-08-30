# `no-type-interrogation` — Nothing dispatches on what kind of thing it was handed

No asking an object what class it is in order to decide what to do with it: no `is_a?`,
`kind_of?` or `instance_of?` as a branch, no case over classes, no `respond_to?` used as a
type test.

**A variant that has to be asked about is not substitutable** — it is a different thing
wearing a shared name. And the ask is the branch that should have been a class: the caller
is deciding on the callee's behalf, which is what
[`no-lifecycle-callbacks`](no-lifecycle-callbacks.md) and
[`no-decisions-in-request-handling`](no-decisions-in-request-handling.md) forbid in their own
places.

**Asserting a type is a different act and is allowed**, at a boundary, where the answer is
to raise rather than to branch — see
[`arguments-are-typed-at-construction`](arguments-are-typed-at-construction.md). The
difference is what happens next: an assertion has one outcome, a dispatch has two.

- **Principle:** `one-way-to-say-each-thing` governs. `tell-dont-ask` also produces it.
- **Guard:** `Shipshape/NoTypeInterrogation`, over the operation, shape and view-component
  trees. Exempts the argument-assertion helper by name, and nothing else.

  **The legacy doors are exempt, by decision rather than by omission.** Adapting a shape the
  old world hands back is what a door is *for* — `row.is_a?(Hash)` over a legacy return value
  is the crossing being made explicit, which is the opposite of the defect this law names.
  Every other rule still binds them, including the two in
  [`nothing-travels-off-the-call-path`](nothing-travels-off-the-call-path.md): a door is new
  code, and only the world on the far side of it is old.

- **Guard's limit:** a genuine boundary check written outside that helper is a **false
  positive**, and it is meant to be argued in review rather than suppressed in silence — a
  suppression comment on this cop should be rare enough to notice. Deserialisation and
  adapter code at a real edge often need the ask, which is why those trees are outside the
  cop's scope rather than exempted inside it.
