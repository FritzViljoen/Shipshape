# `a-test-inherits-what-it-needs` — A test class holds no module, only what it inherits

A test class is independent, as far as independence goes for a thing that runs inside a suite.
It does not `include`, `extend` or `prepend` anything. Everything it needs — an assertion
helper, a way to sign in an actor, a way to travel time — comes from the one base class every
test in the suite inherits.

## This is the base-class argument again

[`one-operation-one-class`](one-operation-one-class.md) already holds this for operations: a
module included into a write puts that module's public methods onto the write from a file
the write's own definition never mentions, so `Shipshape/MixinsAddNothingPublic` forces a
mixin's methods private rather than let an operation's behaviour arrive from somewhere its own
file does not say. [`an-operation-is-a-leaf`](an-operation-is-a-leaf.md) names the same shape
from the other side: a concern defining `anonymous_call` and included into forty writes makes
forty public operations, none of which says so at its own definition.

**A test is no different.** `include SignsInAsAdmin` in a test class does exactly what
`include Paying` does in a write: it puts behaviour on the class from a file nobody reading
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
`Write` and `Read` carries already. `ConfirmBooking.test_call(booking_id: booking.id)` is
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
ratchet below does not watch a single named class: it watches every class or module in a test
tree that is not itself a leaf test — see its own Guard line for exactly what that means and
what it still misses.

## On RSpec, this is a convention with no guard

Neither cop is written against RSpec's own sharing surface. `config.include`, `config.extend`
and `RSpec.shared_context` do exactly what `include SignsInAsAdmin` does in a Minitest test —
put behaviour on a spec from a file the spec itself does not mention — and neither
`Shipshape/NoTestMixins` nor `Shipshape/BaseTestClassGrowth` fires on any of them. `shipshape
install` does not write a base class for RSpec either, for the reason `Install#call`'s own
comment gives: RSpec's sharing is itself a mixin, so there is no honest RSpec form of the one
class this law allows. [`a-guard-states-its-limit`](a-guard-states-its-limit.md) requires this
said plainly rather than discovered: on an RSpec suite, `a-test-inherits-what-it-needs` is a
convention with no guard behind it, and `shipshape check` reporting clean over one proves
nothing.

## Why this is a ban, not a private-methods rule

[`one-operation-one-class`](one-operation-one-class.md) does not forbid `include Paying` in a
write — it forces the mixin's methods private with `Shipshape/MixinsAddNothingPublic`, so the
module's behaviour is still there but nothing outside the write can reach it through the seam
the mixin opened. This law goes further and forbids the `include` outright. The difference is
what the two surfaces cost when they are wrong.

A write with a private mixin still answers through one public method; the class's own
contract is intact even while its internals arrived from elsewhere, and that containment is
what the private-methods remedy is trading on. A test class has no such contract — nothing
calls a test's methods from outside it, so "private" buys a test nothing, and the entire reason
`include SignsInAsAdmin` is worth reaching for is that its methods stay callable exactly the
way a public mixin's would. Forcing test-mixin methods private would not close the door the
operation's rule closes; it would just describe a shape nobody would write. The remedy that
survives for a test is the one that survives for a write with no public surface to protect
by other means: move the behaviour onto the one class already in the inheritance chain.

## Two rejected shapes

**Generated, regenerate-not-edit.** A stricter shape was considered: install rewrites the base
test class every run and treats a local edit as drift to warn about. Rejected — a real suite's
base test legitimately needs setup specific to the application, how *this* app signs in an
actor, what *this* app's time zone is, and a base class that refuses local edits pushes that
need straight back into a module, which is the thing this law exists to close. Nothing about
installation singles this file out: like every other base class `shipshape install` writes,
`Write` included, it is written once and never touched again — `Install#call` skips a target
that already exists, for this file exactly as for every other, and the gem has no drift check
at all.

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
- **Guard's limit:** it sees only the bare directive that opens a class or module — `include`,
  `extend`, `prepend` — and the `extend self` back door onto that same directive. It does not
  see the call site of a module function called directly: `BookingHelper.a_booking(**args)`
  needs no `include` and travels through neither this guard nor, today,
  `Shipshape/NoTestFactories`. `Shipshape/BaseTestClassGrowth` still sees the definition itself
  — `def self.a_booking` inside `BookingHelper` ratchets exactly as a mixin's method would —
  so the growth is visible even where the call site is invisible. Closing the call site is
  that cop's future work, not this one's: construction is `no-test-factories`'s territory, and
  a module-function helper that builds state is a second way to construct it, obeying none of
  the rules `test_call` already enforces. This guard only ever held sharing behaviour and
  assertions between test classes; it was never asked to hold construction.
- **Guard:** `Shipshape/BaseTestClassGrowth`, over every base test class or support module in
  the suite — every file under a `test/` or `spec/` tree, starting with the one `shipshape
  install` writes, `test_case.rb`, that is not itself a leaf test (its name does not end in
  "_test.rb" or "_spec.rb"). A `class` qualifies by its superclass looking like a test's own —
  ending in `Test` or `TestCase` — so an `ActionMailer::Preview` or an `ApplicationRecord`
  living under a `test/` tree, an engine's dummy app being the usual place to find one, is not
  mistaken for a base test class; a `module` always qualifies, because a module has no
  superclass to read and is exactly where the `extend self` back door lives. A `module` has no
  superclass-based escape, so the dummy app is excluded by path instead: `test/dummy` and
  `spec/dummy` are that app's own root, generated once by `rails plugin new` and never hand
  edited, and this cop's own `Exclude` names both, at either nesting. Qualifying nodes are a
  ratchet on two numbers, both only falling, per file: the count of definitions they hold —
  every `def`, `define_method`, `alias_method` and `delegate`, every constant, every `attr_*`,
  every `setup` and `teardown` block, wherever it sits behind an `if` or a block — and the
  qualifying class or module's own size in lines, read from the same investigation that counts
  the first number, not a second walk of the file.
- **Guard's limit:** it identifies a base class by where its file lives, how it is named, and
  what it inherits, never by whether another test actually inherits from it. A helper file that
  happens to be named as though it were a leaf test, or a base class whose superclass does not
  read as a test's own, is invisible to it either way — the same convention that makes the
  ratchet derivable without a checked-in list is what a determined rename or an unconventional
  superclass defeats. Neither number can tell whether a given growth in the base class was the
  reviewed kind or the pressured kind — together they can only make growth visible and
  falling, never judge it. Nor can either see a private module defined and included from inside a
  base class it does watch, which would move the mixin one level down rather than remove it.
  Nor is the dummy-app exclusion itself immune to the same rename: it is a path match on
  `dummy`, so an engine built with `rails plugin new --dummy-path=spec/internal` gets none of
  it, and a module or wrapping config class living there is mistaken for a base test class
  exactly as it would have been with no exclusion at all.

  **And a definition count alone is gamed by inlining:** fold five helpers into one
  two-hundred-line `setup` and the count *falls* while the base class gets worse underneath it.
  [The same principle already governs a cop's clause count](../rails-failure-patterns.md): a
  ratchet gamed by trading one number for another is that failure wearing this law's clothes.
  The second number that closes this hole — the qualifying node's own size in lines — is built
  against this cop's own classification, not a second copy of it: `on_class` and `on_module`
  record the span of every class or module they already decided qualifies, and
  `RuboCop::Formatter::ShipshapeTestClassSizes` reads that record back once the same run ends,
  so a file's classification happens once, in one process, for both numbers. A working version
  existed on an earlier branch and was pulled back out: it reimplemented this cop's
  classification (`qualifying_superclass?`, the module rule, the dummy-app exclusion) a second
  time, in a separate subprocess, and that duplication — not the law, not the offence-count
  half — was where three straight review cycles kept finding new bugs. `Enabled` and `Exclude`
  need no second reading either: a disabled cop or an excluded file never reaches `on_class` or
  `on_module` at all, so nothing is recorded for it, exactly as the offence count sees nothing
  from it.
