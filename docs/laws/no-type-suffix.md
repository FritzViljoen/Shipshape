# `no-type-suffix` — The base class says what a thing is; the name says what it does

`class SettleInvoice < Command` states the shape once. `class SettleInvoiceCommand < Command`
states it twice — the second copy is not read from anywhere, it is retyped by hand at the
point of naming, and nothing keeps it in step with the first.

**The two copies can disagree.** A `Command` reworked into a `Workflow` because a step grew
a second transaction leaves its name still promising the single-transaction shape it no
longer has. A class renamed for what it now does can keep an old suffix nobody remembered to
drop. Either way a reader trusts the name and gets the wrong guarantee, because the one place
this is actually decided — the `< Command` on the line below — was never consulted for it.

**`Service`, `Manager`, `Interactor` and `Handler` name no base class at all.** They are the
shape a class took before this canon gave every operation an ancestor that says what it is,
and a name is not made honest by pointing at nothing. Carrying one forward reads as a
decision this canon already made a different way.

**A name that survives this rule says what the operation does, not what kind of thing it
is** — `SettleInvoice`, not `InvoiceCommand` or `InvoiceService`. What kind of thing it is
has exactly one home, and it is not the name.

- **Principle:** `one-way-to-say-each-thing` — a class's shape is declared once, by
  inheritance, and a suffix restating it is a second way to say the same fact.
- **Guard:** `Shipshape/NoTypeSuffix`, over every governed kind. Refuses a class name ending
  in `Service`, `Manager`, `Interactor`, `Handler`, `Command`, `Query` or `Workflow`, except
  where the name **is** one of the base classes this gem installs — `Command` itself is not
  an offence against a rule about restating `Command`.
- **Guard's limit:** it reads the class name and nothing else, so a name that merely *sounds*
  like a type without matching the closed suffix list — `SettleInvoiceOp`, `InvoiceWorker` —
  passes. It also cannot tell a genuinely bad name from a good one; it only refuses one
  specific way of writing a bad one.
