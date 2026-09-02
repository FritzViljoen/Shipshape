# `one-operation-one-class` — An operation is a class with one public method

One class, one operation, one public method named `call`, taking keyword arguments.

A second public method is a second operation, and it gets a second class. No positional
parameters, no `**rest`, no `(...)` — every input is a named keyword, because a collected
parameter is a hole in every other law that inspects the signature.

**Everything else it does is private.** A public helper on an operation is reachable from
anywhere the class is, so it is part of the contract whether or not anyone meant it to be,
and it cannot be renamed or removed without finding every caller. Under `private` it is what
it was always meant to be — an implementation detail of the one thing this class does. There
may be as many as the work needs.

**A shape is the exception, and it is the only one.** A shape is the presenter level: its job
is to be read, so readers, formatters and values derived from fields it was handed are all
public and all correct. `OperationKinds` leaves shapes out for that reason, and records are
governed instead by
[`persistence-holds-no-behaviour`](persistence-holds-no-behaviour.md), which allows them no
methods at all.

**And it defines that method itself.** The base class's `call` runs whichever of `call` or
`anonymous_call` the class implements, so a class implementing neither has nothing to run —
and one that inherits an entry point from another operation inherits that operation's
answers, including whether it needs an actor at all. Which of the two it is decides whether
the operation is authorisation-checked, so it has to be readable in the file, not two classes
away. `anonymous_call` is the second permitted name and the only one:
[`a-permission-is-the-class-name`](a-permission-is-the-class-name.md) requires it for an
operation that runs before anyone is identified, and a class defining **both** is two
operations with different authorisation sharing one name.

**It answers the same way as every other operation.** A uniform shape is what lets one
wrapper serve every call site: logging, instrumentation, an audit trail, a migration seam.
Four call conventions and none of those can exist.

**Reading and writing are separate classes**, told apart by their names and by what they
do — never by a flag. A flag deciding which of two things a call does is two operations
wearing one name.

**A new case is a new class.** Not by exhortation: a single-method class has nowhere to
grow a branch, and [`the-call-graph-is-declared`](the-call-graph-is-declared.md) gives the
branch nowhere to reach.

**Size an operation so it can be permitted or refused whole.** This is the sizing test, and
it is the one judgement the rest of the model leans on: when deciding what a write or
read should cover, ask who is allowed to do it. If one actor may do half of what it does
and not the other half, it is two operations, and the seam runs exactly where permission
runs.

Getting this wrong is not a naming problem. An operation that spans two permissions has
nowhere to put the refusal: it either checks halfway through and leaves the first half
done, or it takes the widest permission of the two and quietly grants the narrow one. Both
are found in production, and both are re-sizing work by then.

The reverse is just as wrong — splitting one permitted act into three operations means the
caller sequences them, and a caller that can sequence them can stop after the first. **A
permission boundary is a transaction boundary is an operation boundary**, and where those
three disagree the design is not finished.

**Half of this is structural, not advisory.** Because
[the permission is the class name](a-permission-is-the-class-name.md), an operation has
exactly one **of its own** — there is nowhere to put a second, so a class cannot *declare*
itself to be two acts. The first time someone needs to grant half of one, the only available
move is to split it.

What it *demands* is that name plus everything it reaches, derived rather than declared, so
work spanning several permitted acts is expressed by calling them and is refused whole. That is
not a second way to be two acts; it is the same rule reading further.

What stays a judgement is whether the single act you named should have been two.
`SettleAndNotifyInvoice` has one permission and grants both halves, and nothing refuses it —
but the conflation is in the name, on every call site. An operation whose name needs an "and"
is usually two.

**A module included into an operation is held to the same rule.** `include Paying` puts
every one of that module's public methods onto every operation that includes it, and it does
so in a file none of those operations mention — the surface this law closes, reopened where
nobody looks for it. So a mixin's methods go under `private` too.

**A module cannot be judged by its own file**, which is what makes this a separate guard.
`Paying` with public methods is correct in a shape, whose whole job is to be read, and wrong
in a write, which answers one message. Nothing in the module separates those. What decides
is where it is going, so the guard reads the operations and asks what they include.

- **Principle:** `one-way-to-say-each-thing`
- **Guard:** `Shipshape/OneOperationOneClass`, over classes of a kind listed in
  `OperationKinds`. Fails a second public method, a public method not named `call`, a
  public `attr_reader`/`attr_accessor`/`attr_writer` — which is a public method in all but
  name — a class that defines neither `call` nor `anonymous_call`, and any parameter that is
  not a named keyword: positional, optional positional, `*rest`, `**rest`, and `(...)`. Each
  refusal says which it was, because "use keywords" without the reason gets worked around
  rather than fixed. For a second public method it leads with `private`, that being nearly
  always the answer and "give it its own class" the rarer one.
- **Guard:** `Shipshape/MixinsAddNothingPublic`, over modules that an operation includes.
  Fails a public instance method and a public reader, and scaffolds `private` above the
  first of them.
- **Guard:** the generated `operations_expose_nothing_test.rb`, installed into the
  application's own suite.
  **The exact form of this law, and the only one that cannot be fooled.** The cops read
  source; this boots the application and subtracts —
  `SettleInvoice.public_instance_methods - Write.public_instance_methods` is precisely what
  the operation and everything it mixes in added, whatever route it took. It works because
  the base classes are POROs the application owns, with a surface that is known rather than
  guessed. The cops stay because they answer in a second, in an editor, and name the file to
  fix; this one is the guarantee behind them.
- **Guard's limit:** it cannot tell whether the one method does one thing. A two-hundred
  line `call` passes. Class and method length are a separate concern and this cop does not
  cover them. It cannot see a public method added at runtime. `initialize` is exempt —
  Ruby makes it private whatever the file says, and this law requires a hand-written one —
  so a constructor doing the work of an operation is invisible here.

  The layout it reads is declared once, on `Shipshape/CallGraph`, and a file of no declared
  kind is left alone rather than judged.
- **Guard's limit:** the installed test sees only what eager loading loads and only classes
  with a name, so an operation built at runtime is invisible to it. It reports a name, not a
  line — which is the trade for being exact.
- **Guard's limit:** the mixin guard reads `include`/`prepend` with a regular expression over
  the operation trees, so a module mixed in dynamically is invisible, and so is one reached
  through an alias. It compares a written `include Paying` against a module declared `Paying`
  or `Billing::Paying`, which over-fires where two modules share a last segment and only one
  is a mixin — being told to make a module's methods private is defensible, and silence is
  not. It says nothing about `def self.`, which does not travel through `include`.
