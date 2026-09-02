# `a-test-inherits-what-it-needs` — A test class holds no module, only what it inherits

A test class is independent, as far as independence goes for a thing that runs inside a suite.
It does not `include`, `extend` or `prepend` anything. Everything it needs — an assertion
helper, a way to sign in an actor, a way to travel time — comes from the one base class every
test in the suite inherits.

## This is the base-class argument again

[`one-operation-one-class`](one-operation-one-class.md) already holds this for operations: a
module included into a command puts that module's public methods onto the command from a file
the command's own definition never mentions, so `Shipshape/MixinsAddNothingPublic` forces a
mixin's methods private rather than let an operation's behaviour arrive from somewhere its own
file does not say. [`an-operation-is-a-leaf`](an-operation-is-a-leaf.md) names the same shape
from the other side: a concern defining `anonymous_call` and included into forty commands makes
forty public operations, none of which says so at its own definition.

**A test is no different.** `include SignsInAsAdmin` in a test class does exactly what
`include Paying` does in a command: it puts behaviour on the class from a file nobody reading
the test opens. An operation gets its behaviour from the one class it inherits, never from
something mixed in — this is that rule, applied to the suite that tests it.

## Everything a test needs comes from the base class

A test that needs to sign in as an admin does not reach for a module that does it. The base
class gains a method, once, reviewed once, used by every test in the suite from then on. A test
that needs something the base class does not have yet is a reason to change the base class, in
the open, in a diff somebody reviews — not a reason to write a private module and `include` it
where it is needed.

**Construction is not this law's business, and the base class holds none of it.**
[`no-test-factories`](no-test-factories.md) already says how a test builds the state it needs:
by calling the application's own operations, through `test_call`, which every generated
`Command` and `Query` carries already. `ConfirmBooking.test_call(booking_id: booking.id)` is
the shared, named, tested way to reach a confirmed booking, and it lives on the operation's own
base class, not on the test's. So the base test class this law describes holds suite plumbing —
what the framework itself asks for — and nothing that constructs domain state. A test needing a
new way to build something is a reason to look at the operation, not at this class.

## Agents may not simply add to the base class

The base class is the one shared surface a test has left, now that modules are closed. That
makes growing it a decision somebody has to see, not a side effect of getting one test to pass.
An agent under pressure to turn a test green reaches for whatever is closest, and with no module
left to reach for, the closest thing left is the base class. Adding a method there to satisfy
one test is the same move the module would have been, wearing the one name this law still
allows.

## A second base class is the same hole one level down

Closing modules does not by itself make the base class singular. `class AdminTestCase <
ActiveSupport::TestCase` holding shared helpers is fully legal under "no `include`" and is
outside a ratchet that watches only one named file — an agent asked to remove an `include`
this law forbids can satisfy it by moving the same methods onto a new intermediate class
instead of onto the one the application already installed, and nothing above has moved. So the
ratchet below does not watch a single named class: it watches every class in a test tree that
is not itself a leaf test — see its own Guard line for exactly what that means and what it
still misses.

## Two rejected shapes

**Generated, regenerate-not-edit.** The base test class could have been installed the way
`Command` is: owned by the gem, redistributed on update, any local edit read as drift. Rejected
— a real suite's base test legitimately needs setup specific to the application, how *this* app
signs in an actor, what *this* app's time zone is, and a base class that refuses local edits
pushes that need straight back into a module, which is the thing this law exists to close.
Nothing about installation changes for this file: like every other base class `shipshape
install` writes, it is written once and never touched again — `Install#call` skips a target
that already exists, for this file exactly as for every other.

**A public-method-count ratchet, alone.** Counting only the base class's public methods was
considered and rejected. Private is exactly where an agent under this law puts
`build_admin_actor` once it cannot make a module of it — nothing about `include`-free code
requires the helper to be public — and a public-only count never moves while the base class
gets worse underneath it.

## Why now

Shipshape is about to be used to refactor a real codebase using agents, and the purpose of
closing these doors before that starts is to find out which door the agents reach for instead —
a guard set is only tested by something actively trying to get work done through it.

- **Principle:** `nothing-is-hidden` governs — a module's methods live in a file the test never
  mentions, which is the same defect named above from an operation's side.
- **Guard:** `Shipshape/NoTestMixins`, over the test trees — fails `include`, `extend` and
  `prepend` naming anything but the language's own modules.
- **Guard's limit:** it sees only the bare directive that opens a class or module. It does not
  see `def self.` on a module called directly — `BookingHelper.a_booking(**args)` needs no
  `include` and travels through neither this guard nor, today, `Shipshape/NoTestFactories`.
  Closing that door is that cop's future work, not this one's: construction is
  `no-test-factories`'s territory, and a module-function helper that builds state is a second
  way to construct it, obeying none of the rules `test_call` already enforces. This guard
  only ever held sharing behaviour and assertions between test classes; it was never asked to
  hold construction.
- **Guard:** `Shipshape/BaseTestClassGrowth`, over every base test class in the suite — every
  file under a `test/` or `spec/` tree, starting with the one `shipshape install` writes,
  `test_case.rb`, that is not itself a leaf test (its name does not end in "_test.rb" or
  "_spec.rb") — a ratchet on two counts, both only falling, per file: every definition the
  class holds regardless of visibility — every `def`, every constant, every `attr_*`, every
  `setup` and `teardown` block — and the body size of the class in lines. Two numbers rather
  than one because either alone is gamed by the other's slack: a definition count is gamed by
  inlining — fold five helpers into one two-hundred-line `setup` and the count falls while the
  base class gets worse — and a size count is gamed by golf. [The same principle already
  governs a cop's clause count](../rails-failure-patterns.md): it measures how many ways the
  code can say one thing, and a ratchet gamed by trading one number against the other is that
  failure wearing this law's clothes.
- **Guard's limit:** it identifies a base class by where its file lives and how it is named,
  never by whether another test actually inherits from it. A helper file that happens to be
  named as though it were a leaf test, or a base class defined inside a file this heuristic
  does not reach, is invisible to it either way — the same naming convention that makes the
  ratchet derivable without a checked-in list is what a determined rename defeats. Neither number,
  once built, can tell whether a given growth in the base class was the reviewed kind or the
  pressured kind — it can only make growth visible and falling, never judge it. Nor can it see
  a private module defined and included from inside a base class it does watch, which would
  move the mixin one level down rather than remove it.
