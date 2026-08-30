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
hash. This is the same instrument as
[`one-operation-one-class`](one-operation-one-class.md)'s installed test: where a cop can only
read names, the loaded object answers exactly.

- **Guard:** `Shipshape/ShapeIsComposed`, over the shape tree. Fails an initializer keyword
  whose name is prefixed with the name of another declared domain object, where that object
  declares the suffix as one of its own.

- **Guard's limit:** **the prefix rule is a heuristic and the general law is unguarded.**
  It catches the naming convention that flattening usually arrives in, and nothing else — a
  copied field under a different name is invisible, and a legitimate field that happens to
  share a prefix is a false positive to be argued in review. Whether two things belong in one
  object is a judgement, and no check makes it; the heuristic exists because the
  *convention* is catchable even though the *rule* is not.
