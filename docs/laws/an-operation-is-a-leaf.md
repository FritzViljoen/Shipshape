# `an-operation-is-a-leaf` — A base class is inherited exactly once, and its door is not overridable

`SettleInvoice < Command` is an operation. `AdminSettleInvoice < SettleInvoice` is not, and
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
`anonymous_call` and included into forty commands makes forty public operations, none of
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

**Tests are exempt, and deliberately.** A test builds objects directly, reaches private
methods and stubs what it needs — that is what a test is for, and refusing it would make this
the first cop a team turns off. The advice still stands where it applies: what the door does
*is* part of the behaviour, so a test that skips it passes while the operation is
unauthorised. That is a judgement for the person writing the test, not a rule the build
holds.

## What to do with the thing you wanted to share

Make it a collaborator, not an ancestor. Two operations that share work call a third:

```ruby
class AdminUpload < Command
  def call
    Upload.call(actor: actor, file: @file)
  end
end
```

That is a command calling a command, which the matrix refuses — so the shared part is a
query, or the sequence is a workflow. **The call graph already had an answer for this**; the
inheritance was a way of not using it.

- **Agreed:** Fritz, 2026-08-30 — asked for a guard that only `self.call` is ever called on an operation, and that internals are not reachable from outside.
- **Principle:** `nothing-is-hidden` governs — a guarantee decided two classes away is a
  guarantee the reader cannot see. `good-boundaries-make-good-neighbours` produces the
  collaborator half.
- **Guard:** the generated `command.rb`, `query.rb`, `workflow.rb`, `io_command.rb`,
  `io_query.rb`, `legacy_command.rb` and `legacy_query.rb` — architecture. Each owns
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
  `app/queries/` resolves to an operation kind by path alone, and `ApplicationMailer` is
  named in the layout so kinds resolve — neither makes the hierarchy below it ours. Applying
  the rule to them fired on every mailer in chatwoot and every operation in a repository that
  files `Command` beside its commands.
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
