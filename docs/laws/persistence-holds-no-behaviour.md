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
  whose body only filters on this table's own columns.
  **Not built yet** — so this is a convention today, held by review. The law is
  written anyway: a rule nobody wrote down cannot be built later.

- **Guard's limit:** it cannot tell a filtering scope from a rule-bearing one beyond a
  syntactic check on the block, so a scope that reaches another class inside a lambda passes.
  It sees the record tree only — behaviour moved into a helper, a module included from
  outside that tree, or a query object filed elsewhere is not covered. And it says nothing
  about whether the record's columns belong together, which is the actual god-object
  question and the one no check answers.
