# Sweeping the call sites — the step that lands every other one

A procedure, meant to be followed by an agent one step at a time. Every step ends with
something to **run**, because a decomposition nobody can verify is a rewrite with extra
confidence.

**What you are aiming at:** every call site of the thing you are changing moved in **one
commit**, with the callee changed last. Not a compatibility shim, not a deprecation warning, not
two spellings living side by side while the sweep finishes — because the half-swept state is the
one where a reader cannot tell which spelling is current, and it is the state that lasts.

The check is that the old name returns nothing:

```sh
grep -rn "OldName" app lib spec test
```

**Every other procedure here takes one class apart. This one is the opposite shape:** one
decision, repeated across every caller of the thing you just moved. It is the largest single
category of work in the corpus this canon was measured against — 1,883 sites across seven
repositories — and it is the step that decides whether an extraction landed or left a trail
of broken callers.

It is also the step an agent is most likely to get wrong, because it is boring, mechanical,
and looks finished long before it is.

---

## 0. Know what you are sweeping, before you sweep

```sh
shipshape next --json
```

`OnlyTheDoorIsCalled` names every site. The list is the work — nobody has to go looking, and
nobody should:

```text
app/controllers/invoices_controller.rb:31  SettleInvoice.new(invoice) is not the door
app/jobs/settle_job.rb:12                  SettleInvoice.new(invoice) is not the door
```

**Do not start from `grep`.** A grep for `SettleInvoice.new` finds the sites that spell it
that way and misses `Invoices::SettleInvoice.new`, `::SettleInvoice.new`, and the one behind
an alias. The cop resolves the constant instead, which is why it is the enumeration and grep
is not.

**Check:** the count of `OnlyTheDoorIsCalled` offences is the number of sites you are about
to change. Write it down; it is the only number that says when you are finished.

---

## 1. Change the callee last, not first

The order that works:

1. the new door exists and is called by nothing
2. every call site moves to it
3. the old entry point is deleted

The order that does not work is starting at step 3, or doing 1 and 3 together. **A caller you
have not found yet is the failure mode**, and it is silent in Ruby until the line runs — no
compiler, no signature check, and a `NoMethodError` in production at whatever hour that branch
first executes.

Keeping the old shape alive while the sites move means the tree is green at every point, and
the sweep can stop halfway without anything being broken.

**Check:** `shipshape check` — the count falls at each slice and never rises.

---

## 2. Move the arguments to keywords, and read each one

`SettleInvoice.new(invoice, today, true).call` becomes
`SettleInvoice.call(invoice_id: invoice.id, settled_on: today, notify: true)`.

**This is the part that is not mechanical, and the part an agent will treat as though it
were.** Three things change at once and each needs the site read:

- **A positional becomes a named keyword**, and the name has to be right. `true` in position
  three tells you nothing; whoever writes `notify:` has decided what it meant. Get it from the
  callee's parameter list, never from the call site.
- **A record becomes an id.** A record is not an argument — `arguments-are-typed-at-construction`
  refuses one at `typed`, and the generated base classes refuse one at construction. The caller
  usually already has the record, so `invoice` becomes `invoice.id` and the operation loads
  what it needs.
- **The order stops mattering**, which is what makes the next reordering safe, and is most of
  the reason for doing this at all.

**Check:** `TypedArguments` is silent on the callee, and `ReadsWriteNothing` has not appeared at
the call site (a caller that was passing a record it had just written is a caller doing the
operation's job).

---

## 3. Take the answer apart at the same site

The old call answered anything: a record, `nil`, `false`, a hash, a raised exception. The new
one answers a `Result` for a write, shapes for a read. **The call site is where that lands,
and the two changes belong in one edit** — split across two passes, the intermediate state has
callers reading a `Result` as though it were a record, which is green in Ruby and wrong.

```ruby
# before — nil means "not found", false means "refused", and nothing says which
invoice = SettleInvoice.new(invoice).call
redirect_to invoices_path unless invoice

# after
result = SettleInvoice.call(actor: current_user, invoice_id: invoice.id)
return redirect_to invoices_path, alert: t(result.error) if result.failure?
```

**Where the old code rescued, look twice.** A `rescue` around the old call was catching an
expected failure the callee raised, and expected failures are now values — see
[a swallowed error](a-swallowed-error.md). A rescue left in place around a call that no longer
raises is dead code that reads as caution.

**Check:** `NoEmptyRescue` has not increased, and the callee's base class does not raise
`TypeError` at the door (which is what it does when a subclass answers with the wrong shape).

---

## 4. The sites a cop cannot see

`OnlyTheDoorIsCalled` reads the call site and resolves the constant. It cannot see:

- **an operation held in a variable** — `klass = SettleInvoice; klass.new(...)`
- **a constant built from a string** — `"SettleInvoice".constantize`, a registry, a lookup
  table of class names
- **anything in a test**, which is exempt on purpose

So after the cop goes quiet, the sweep is not finished. Search the ways the cop cannot:

```sh
grep -rn "constantize\|const_get\|safe_constantize" app lib
grep -rn "SettleInvoice" app lib config       # the plain name, everywhere
```

`private_class_method :new, :allocate` is what catches the survivors — at runtime, on the
first call, which is exactly why they should be found here instead. `NoEntryPointBypass` names
the deliberate ones: a `send(:new)` or a `public_send(:__perform__)` written to get around the
private constructor, usually by somebody who met it mid-sweep and wanted to move on.

**Check:** both greps return nothing that names the operation, and the test suite runs.

---

## 5. Delete the old entry point, and mean it

The old `def call` on the old class, the old `self.for`, the old factory. **A second entrance
left behind is worse than the original**, because the codebase now has two ways to do one
thing and only one of them is guarded — `one-way-to-say-each-thing`, and the site using the
old way is invisible until it fails.

If something outside this repository calls it, that is a different problem with a different
answer (a deprecation, a version, a door of its own) — not a reason to leave it.

**Check:** `OnlyTheDoorIsCalled` reports zero for that operation, and the number you wrote
down in step 0 has been accounted for site by site.

---

## What this leaves you

**One spelling, everywhere, from one commit.** A reader never has to work out which of two
names is current, because there was never a window in which both were. The cost is a bigger
diff; what it buys is that `git log` has one entry for the change rather than a trail nobody
can bisect.

## What none of this proves

**Nothing here shows the callers still behave.** Every check above passes if the arguments
were reordered wrongly, as long as they are keywords — that is the whole point of keywords,
and it is also why a wrong one is quiet.

The two failures worth expecting: **a keyword named from the call site rather than the
callee**, which reads fine and means something else; and **a `Result` treated as truthy**,
because a `failure` object is truthy in Ruby and `if result` is true for both outcomes.

Neither is caught by anything here. Both are caught by a test that calls the operation and
asserts what it answers, which is the reason to write that test before the sweep rather than
after it.
