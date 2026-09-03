# `persistence-holds-no-behaviour` — A record maps rows and holds no rules

A record class declares its columns and its associations. Nothing else: no business method,
no calculation, no lifecycle callback, no scope that encodes a rule rather than a filter.

**The domain object is a different class.** It is built by an operation, composed from
values, and **detached from the database** — so a reader holding one cannot query or write
through it by accident, and the thing's shape stops being whatever the table happens to
have.

**The names say which is which.** A record's name says it stores; a domain object's name
says what it is. `SupplierRecord` never leaves the operation tree; `Supplier` is what
travels.

This is the first half of taking a god object apart. The second is
[`a-shape-is-composed-not-flattened`](a-shape-is-composed-not-flattened.md), and doing
one without the other just moves the pile.

- **Principle:** `model-concerns-not-groups` governs. `tell-dont-ask` also produces it — a
  record answering questions about itself is the record deciding on the caller's behalf.
- **Guard:** `Shipshape/PersistenceHoldsNoBehaviour`, over the record tree. Fails any public
  method outside a declared allowlist: association and attribute declarations, and scopes
  whose body only filters on this table's own columns. **`default_scope` fails on neither
  test**: it is implicit behaviour rather than a declared rule — global state entering every
  read, and a distant write leaving with every `create`. It is caught here because a record
  is where it is written, but the law it offends is
  [`nothing-travels-off-the-call-path`](nothing-travels-off-the-call-path.md), in both
  directions at once. **`delegate` and `delegate_missing_to` fail too**: they write the methods
  `def` would have written, so they were the one way left to put behaviour on a record.

- **Guard's limit:** it cannot tell a filtering scope from a rule-bearing one beyond a
  syntactic check on the block, so a scope that reaches another class inside a lambda passes.
  It sees the record tree only — behaviour moved into a helper, a module included from
  outside that tree, or a query object filed elsewhere is not covered. `delegate` is caught
  **here and only here** — [`code-is-written-not-generated`](code-is-written-not-generated.md)
  exempts the framework's public macros on purpose and uses this one to draw that line, so a
  delegating shape or component is not covered by either law. And it says nothing about whether the
  record's columns belong together, which is the actual god-object question and the one no
  check answers.
