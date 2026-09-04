# Decomposing a shared concern — a module is not a place to put things

A procedure, meant to be followed by an agent one step at a time. Every step ends with
something to **run**, because a decomposition nobody can verify is a rewrite with extra
confidence.

**What you are aiming at:**

```ruby
# before — the module reaches into whoever included it
module Paying
  def total
    @lines.sum(&:amount)      # @lines belongs to somebody else
  end
end

# after — what was shared is a collaborator, not an ancestor
class Total
  def self.of(lines) = lines.sum(&:amount)
end
```

A module that reads the includer's state is inheritance wearing a smaller word. Passing what it
needs makes the dependency visible at the call site, which is where a reader is looking.

The shape: `app/models/concerns/paying.rb`, included by nine services, defining eleven public
methods. 470 offences across seven repositories, and the reason they are hard to see is that
**the module looks small**. The class that includes it is where the size went.

**A concern that obliges its includers to carry columns is a different shape** and has its own
procedure — [a record concern](a-record-concern.md). The test is whether removing the module
would leave columns behind: if it would, the schema is the problem and the methods are not.

---

## 0. Find out who includes it, and what that makes them

```sh
shipshape next --json
```

`MixinsAddNothingPublic` only fires on a module an operation actually includes, which is the
first fact you need: the same module with public methods is **correct** in a shape, whose whole
job is to be read, and wrong in a deed, which answers one message.

Then list the includers by hand, because the cop does not print them:

```sh
grep -rln "include Paying" app lib
```

**Check:** you have the list of including classes and their kinds before touching the module.

---

## 1. Decide what the module is, and there are only three answers

| What it is | What it becomes |
|---|---|
| helpers the includers each use privately | `private` in the module — a one-line fix, and most of them |
| an operation the includers each perform | its own class, called by each of them |
| a **thing** the includers each have | a shape, held as a field |

**The third is the one that gets missed, and it is the one worth the effort.** `Paying` with
`amount`, `currency`, `charged_at` and four methods over them is not a mixin — it is a `Money`
or a `Payment` that nobody has written yet, and every includer is carrying its fields
flattened. That is `a-shape-is-composed-not-flattened` arriving as a module instead of as
columns.

The test is the same as everywhere: **when this changes, what else changes with it?** Methods
that always change together are one thing; methods that share only a prefix are a filing
cabinet.

**Check:** none. This is the judgement the procedure exists to leave room for.

---

## 2. Take the easy ones first — `private` and stop

For a module that really is shared private helpers, the fix is one line and the autofix
writes it:

```sh
shipshape check --fix          # or: rubocop -A --only Shipshape/MixinsAddNothingPublic
```

**Do this before anything structural.** It empties the list down to the modules that need a
decision, and it does not move any code — which makes the diff worth reading rather than
worth skimming.

**Check:** `MixinsAddNothingPublic` falls; nothing else moves.

---

## 3. Watch for the module that carries state

```ruby
module Paying
  def total
    @lines.sum(&:amount)      # @lines belongs to whoever included this
  end
end
```

An ivar the module did not set is the module reaching into its includer, and it is why
`include` felt necessary. **This is what makes the module unmovable**, and it is why it must
be fixed before the split, not after: a method that reads `@lines` cannot become a class
until `lines` is an argument.

Thread each one through as a parameter first, in place, while it is still a module. Then it
moves.

**Check:** the module's methods name no instance variable it did not set.

---

## 4. Split by includer, not by method

The trap: turning an eleven-method module into eleven private methods repeated across nine
classes, or into one eleven-method class every includer now depends on.

Ask per includer: **which of these does it actually use?** Almost always the answer is "three
of the eleven", and different threes. A module included nine times for three methods each is
three things, and each of the three has a different set of users.

`shipshape next` ranks by coverage, so the includer with tests goes first.

**Check:** after the split, no class includes something for less than half of what it defines.

---

## 5. Concerns that include concerns

`MixinsAddNothingPublic` reads `include`/`prepend` with a regular expression over the
operation trees. **A concern that includes another concern is invisible to it** — only the
outermost one is named by an operation, so the inner one is somebody else's business as far
as the cop is concerned.

The installed `operations_expose_nothing_test.rb` is what catches those: it subtracts the base
class's public surface from the loaded operation's, so a method arriving three concerns deep is
counted like any other.

```sh
bundle exec rails test test/shipshape/operations_expose_nothing_test.rb
```

**Check:** that test is green, which is a stronger statement than the cop being quiet.

---

## What this leaves you

**Dependencies visible at the call site.** What the code needs is passed to it rather than
reached for through an ancestor, so a reader can tell what a class uses without opening the
modules it includes, and two includers can no longer disagree about what `@lines` means.

## What none of this proves

**Nothing here shows the includers still work.** Moving a method from a module to a class
changes what `self` is inside it, and a method that quietly used the includer's other methods
compiles fine and answers differently.

The reliable failure: **a module method that called another module method**, where both moved
to different places. Both exist, both are callable, and the one calling the other now reaches
a different object. Nothing in this procedure catches it and the test suite is the only thing
that will.
