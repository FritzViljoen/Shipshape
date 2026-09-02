# `an-operation-is-a-leaf` — A base class is inherited exactly once, and its door is not overridable

`SettleInvoice < Write` is an operation. `AdminSettleInvoice < SettleInvoice` is not, and
the depth is what makes the model unsafe rather than merely untidy.

**Everything the door decides, it decides for the class in front of it.** The permission
check, the transaction, the return-type assertion — all of it is `self.call` looking at one
class. A second level inherits those answers *without appearing to ask the question*, and
that is the whole defect: the file you are reading says nothing, and the thing that decided
is two hops away.

The concrete failure, found by review rather than by argument: `class AdminUpload <
PublicUpload`, where the parent implemented `anonymous_call`. `AdminUpload` ran with no actor
and no check, dispatching to its parent's method — and `grep -rn "def anonymous_call"`, which
[`a-permission-is-the-class-name`](a-permission-is-the-class-name.md) calls the whole set of
public operations, did not name it. The predicate was fixed to stop walking ancestors; **this
law removes the shape that made the question worth asking.**

**A module is the same defect wearing different clothes.** A concern defining
`anonymous_call` and included into forty writes makes forty public operations, none of
which says so at its own definition.

**And the door itself is not overridable.** `def self.call` in an operation replaces the base
class's entry point and takes the check, the transaction and the type assertion with it. The
replacement reads as ordinary code: every caller still writes `SettleInvoice.call(...)`, and
nothing at the call site indicates the guarantees are gone.

## Going around the door is refused at the call site, not by `private`

`SettleInvoice.call(...)` is the only supported way in, and what holds that is a check on the
**call site** rather than a keyword on the method. `Shipshape/OnlyTheDoorIsCalled` resolves
the constant and refuses any message an operation does not answer — `.new`, `.build`,
`.for`, the forwarder — wherever it is written and whatever the visibility of the thing it
names.

**`call` and `anonymous_call` stay public**, and `private` goes above the first helper, which
is the shape every Rails codebase already writes. Hiding the entry point as well was tried
and dropped: it bought a runtime backstop against a hole that already required constructing
an operation, and construction is separately refused. The base class dispatches with an
implicit receiver, so it works either way — an application free to make its own `call`
private loses nothing.

**The constructor is private.** `private_class_method :new` says at runtime what the call-site
check says at build time: nobody outside builds an operation. `send` undoes it, which is why
it is not the guarantee — `Shipshape/NoEntryPointBypass` fails `send`, `__send__`,
`public_send` and `method` where they name `new` or the forwarder.

**Every one of those is a convention Ruby steps over.** `private` is not a wall, `send` undoes
`private_class_method`, and a subclass can redeclare a private method public. Each is worth
having and none is the check. The check reads the call site.

**`OnlyTheDoorIsCalled` does not read the test trees**, so nothing here fails a test that
constructs an operation directly.

**That is a gap rather than a licence, and another law now closes most of it.**
[`no-test-factories`](no-test-factories.md) says a test builds state by calling operations,
because a factory can build a row the application cannot — and `Operation.new(...)` in a test
is the same second construction with a different spelling. `Shipshape/NoTestFactories` reads
the test trees and catches the factory libraries by name; a bare `new` is not on its list, and
that is the residue.

What the door does *is* part of the behaviour, so a test that skips it passes while the
operation is unauthorised. The declared way to skip only the permission check is `test_call`,
which raises outside the test environment; anything further is a judgement for the person
writing the test.

## What to do with the thing you wanted to share

Make it a collaborator, not an ancestor. Two operations that share work call a third:

```ruby
class AdminUpload < Write
  def call
    Upload.call(actor: actor, file: @file)
  end
end
```

That is a write calling a write, which the matrix refuses — so the shared part is a
read, or the sequence is a workflow. **The call graph already had an answer for this**; the
inheritance was a way of not using it.

- **Principle:** `nothing-is-hidden` governs — a guarantee decided two classes away is a
  guarantee the reader cannot see. `good-boundaries-make-good-neighbours` produces the
  collaborator half.
- **Guard:** the generated `write.rb`, `read.rb`, `workflow.rb`, `io_write.rb`,
  `io_read.rb`, `legacy_write.rb` and `legacy_read.rb` — architecture. Each owns
  `self.call`, and `private_class_method :new, :allocate` means a caller cannot build one
  to go around it.
- **Guard:** `Shipshape/OnlyTheDoorIsCalled` is the one that does not rely on visibility:
  it reads the call site, resolves the constant, and refuses any message an operation does
  not answer — `new`, `build`, `__perform__`, anything but `call` and the small class-level
  API for asking about an operation without running it. **Everything else here is a
  convention Ruby steps over**, which is why this exists: `private` is not a wall, `send`
  undoes `private_class_method`, and a subclass can redeclare a private method public.
  `Shipshape/NoEntryPointBypass` holds the call site — `send` and its family,
  where they name an entry point, anywhere but the generated base classes.
  `Shipshape/OperationsAreLeaves`, over the operation kinds, Fails a class whose
  superclass is itself an operation **rooted in a base class shipshape installs**, and fails
  `def self.call` in one.

  **The depth rule is about this canon's base classes and no others.** A plain class in
  `app/reads/` resolves to an operation kind by path alone, and `ApplicationMailer` is
  named in the layout so kinds resolve — neither makes the hierarchy below it ours. Applying
  the rule to them fired on every mailer in chatwoot and every operation in a repository that
  files `Write` beside its writes.
  A door spelled `define_singleton_method(:call)` is refused by
  [`code-is-written-not-generated`](code-is-written-not-generated.md) rather than here.
  **Depth outside this canon's hierarchy is a smell, and the report counts it.** "Inheritance
  deeper than one level" in `shipshape report` names every chain of three the repository
  declares — `Mod::ActivitiesController < Mod::ModController < ApplicationController` is the
  usual shape, an intermediate base class where behaviour accretes and which belongs to
  nobody. It is reported and not guarded, and the measure says so where it is read.
- **Guard's limit:** it reads the **superclass constant**, so `Class.new(SettleInvoice)` and
  any superclass it cannot resolve to a governed file are invisible. It cannot see a module
  that redefines `call` after inclusion, nor an included module carrying `anonymous_call` —
  that one is held by the base class's `anonymous?`, which looks at the class itself and no
  ancestor. Depth is measured through governed files only: an operation inheriting from
  something in an undeclared tree is left alone rather than guessed at.
