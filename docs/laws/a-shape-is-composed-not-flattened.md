# `a-shape-is-composed-not-flattened` — A domain object holds another; it never copies its fields

Where one domain object needs another, it holds that object as a **field**. It does not copy
that object's attributes onto itself.

`Booking` holding `supplier_name`, `supplier_email`, `supplier_phone` has taken three of
`Supplier`'s columns and made them its own. Now a change to what a supplier is touches two
classes, and the copies drift. **A flattened field is the first column of the next god
object** — this is the mechanism by which a hundred-column table happens, one reasonable
addition at a time.

**A domain object validates its own shape and computes nothing.** Holding a shape and
deriving a value are different jobs; deriving is an operation's, and a shape is not an
operation.

- **Principle:** `model-concerns-not-groups` governs. `good-boundaries-make-good-neighbours`
  also produces it — a copied field is a second home for one fact.
**A shape never holds a record, and an argument is how one gets in.** The call graph stops a
shape *naming* a record. It cannot stop `ProfileShape.new(person: PersonRecord.find(1))`,
because at the shape there is no record anywhere in the source — there is a keyword called
`person`, and nothing a cop reads says what it holds. Every other rule about shapes leaks
through that one argument: a shape holding a record lazily loads associations, writes through
them, and reopens the database from the presentation layer, with `@person.orders` and no
constant for anything to see.

So the generated `Shape` refuses it on construction, where the object is in hand and can
simply be asked what it is — reaching a record smuggled in under any name, in an array, in a
hash. The generated `ApplicationViewComponent` refuses it the same way, through the same
module: a component is the other presentation kind, and a component holding a record renders
a template that queries — the N+1 nobody can find, because the call causing it is in an
`.erb` file and names nothing.

This is the same instrument as [`one-operation-one-class`](one-operation-one-class.md)'s
installed test: where a cop can only read names, the loaded object answers exactly. The rule
itself is general and belongs to
[`arguments-are-typed-at-construction`](arguments-are-typed-at-construction.md) — a record is
not an argument anywhere; this is where the presentation layer is held to it.

- **Guard:** the generated `shape.rb`, `application_view_component.rb` and
  `holds_no_records.rb` — architecture. Both presentation kinds sweep what they were built
  holding and refuse a record, whatever name it arrived under.
- **Guard:** `Shipshape/ShapeIsComposed`, over the shape tree. Fails an initializer keyword
  whose name is prefixed with the name of another declared domain object, where that object
  declares the suffix as one of its own.

- **Guard's limit:** **the prefix rule is a heuristic and the general law is unguarded.**
  It catches the naming convention that flattening usually arrives in, and nothing else — a
  copied field under a different name is invisible, and a legitimate field that happens to
  share a prefix is a false positive to be argued in review. Whether two things belong in one
  object is a judgement, and no check makes it; the heuristic exists because the
  *convention* is catchable even though the *rule* is not.

  **"Computes nothing" is unguarded, and deliberately.** A shape holding `@cents` and
  answering `@cents * 1.15 + 100` passes everything here. Separating a field that is read
  from a value that is derived needs a judgement about what the number means, and no check
  makes it — a formatter is fine, a tax calculation is an operation wearing a shape's clothes,
  and both are arithmetic on a field. Named here so the silence is a stated limit rather than
  a hole somebody finds later.

  A shape with **no** initializer is not reported: a value with no state is legitimate. Nor is
  a public class method — `Money.from_cents` is a value constructor, and a shape's whole job
  is to be read, which is why the rule that an operation exposes only `call` does not reach
  here.
