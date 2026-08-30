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

## What to do with the thing you wanted to share

Make it a collaborator, not an ancestor. Two operations that share work call a third:

```ruby
class AdminUpload < Command
  def call
    Upload.call(actor: @actor, file: @file)
  end
end
```

That is a command calling a command, which the matrix refuses — so the shared part is a
query, or the sequence is a workflow. **The call graph already had an answer for this**; the
inheritance was a way of not using it.

- **Principle:** `nothing-is-hidden` governs — a guarantee decided two classes away is a
  guarantee the reader cannot see. `good-boundaries-make-good-neighbours` produces the
  collaborator half.
- **Guard:** `Shipshape/OperationsAreLeaves`, over the operation kinds. Fails a class whose
  superclass is itself an operation, and fails `def self.call` in one.
- **Guard's limit:** it reads the **superclass constant**, so `Class.new(SettleInvoice)` and
  any superclass it cannot resolve to a governed file are invisible. It cannot see a module
  that redefines `call` after inclusion, nor an included module carrying `anonymous_call` —
  that one is held by the base class's `anonymous?`, which looks at the class itself and no
  ancestor. Depth is measured through governed files only: an operation inheriting from
  something in an undeclared tree is left alone rather than guessed at.
