# Decomposing a service — the order, and how each step is checked

A procedure, meant to be followed by an agent one step at a time. Every step ends with
something to **run**, because a decomposition nobody can verify is a rewrite with extra
confidence.

It assumes a 600-line service with fifteen public methods, which is the shape this is for.
Other shapes have their own procedure — see [the index](README.md), which also carries the
one step they all share and the test for what belongs in a table.

**What you are aiming at:**

```ruby
# before
BookingService.new(booking).confirm!          # one of fifteen public methods

# after — one class per act, and the name says which
ConfirmBooking.call(actor: actor, booking_id: id)   # answers success(...) or failure(:code)
FindBooking.call(id: id)                            # answers a shape, or nothing
```

Fifteen public methods become fifteen classes, each named for what it does, each with its own
permission — because [a permission is the class name](../laws/a-permission-is-the-class-name.md).
That is the whole shape; the steps below are how to get there without a red suite.

---

## 0. Make the file visible, or nothing below is true

```sh
shipshape coverage
```

`app/services` matches no default glob. Until it is declared in `Shipshape/CallGraph`'s
`Kinds`, every kind-scoped cop skips the file and reports it clean — which reads as "this
code is fine" and means "nothing looked at it". **This is the most common way the whole
exercise goes wrong**, and it is silent.

Declare the tree as `legacy_read` or `legacy_write` — a legacy door is exactly a wrapper
around old code — or as `read`/`write` if you intend to convert rather than wrap.

**Check:** the file appears in `shipshape next`.

---

## 1. Read what it already tells you

```sh
shipshape next --json
```

The cops have already done the enumeration:

- **`OneOperationOneClass` fires once per public method.** Six offences means six operations,
  and they are named. Nobody has to decide what to split — the list exists.
- **`TypedArguments`** names every input that arrives unasserted. That is the constructor of
  whatever the pieces become.
- **`NoAmbientReads`** names every dependency that is not on the call path — `Time.current`,
  `ENV`, `current_user`. Each becomes an argument.
- **`NoTypeInterrogation`** names the places a variant should have been a class.

And the cops are not the only free list. **Every `transaction do` in the service is a write
somebody already named**, because they decided those writes were one act — see
[the index](README.md), "Start from the transaction blocks". It is the one boundary in a
legacy file that was not inferred. Extracted into a `Write`, that block's own `transaction`
line is deleted — the base class already opens it — and `Shipshape/OperationsOpenNoTransaction`
is what catches one written back in.

**Check:** you can list the target classes before writing any of them.

---

## 2. Take the reads and the writes apart first

One method that reads and writes is two operations sharing a name, and the split is not a
judgement — a read answers shapes, a write answers a `Result`. Do this before anything
else, because every later decision depends on which side a piece is on.

**Check:** `shipshape check` — the count falls, and no `CallGraph` offence appears (a read
that writes will show up as reaching something it may not).

---

## 3. Thread the ambient reads out

Every `Time.current`, `ENV[...]`, `current_user` becomes a keyword on the constructor,
asserted with `typed`. Do this **before** splitting, not after: an ambient read hides which
piece actually depends on what, and two pieces that both call `Time.current` look
independent until they are not.

**Check:** `NoAmbientReads` is silent on the file. `NoDistantWrites` too — a service that
mutated a global or a constant in place was passing state to its next caller through the
floor, and that is the same dependency with no name at all.

---

## 4. Find the data pretending to be code

```text
Rules that are really data — 6
  app/models/email.rb:39  3 branches over status, each answering with a literal
```

A `case` over domain literals answering with literals is a lookup table someone wrote as
code. `status → colour`, `levy → rate`, `country → tax`.

**This is why the service grew.** Each new case is one more branch in a method that already
had five, and the method grew because the *data* grew — the one kind of growth that
refactoring never fixes, because the code was never the problem. Split a fifteen-method
service into fifteen classes and the branch is still there, in one of them, still needing a
deploy to add a row.

Move it to a table before splitting. The test is whether the branch encodes a fact **somebody
outside the team owns** — a rate, a fee, a term of art, a status the business named. Those
are rows. A branch on a nil, a size, a boolean is control flow and stays.

**Check:** "Rules that are really data" falls in `shipshape report`.

---

## 5. Split by what changes together, not by what looks alike

`model-concerns-not-groups`. The temptation is to group by shape — all the finders, all the
formatters — because that is what the eye sees. It produces classes that always change
together and a diff that touches all of them.

Ask instead: **when this changes, what else must change with it?** Pieces that answer the
same question to the same person belong in one operation, however different they look.
`AnalyticsService#totals` and `#grouped` look alike and change apart; `#totals` and the
clamping it does change together.

**Check:** none. This is the judgement the whole procedure exists to leave room for, and no
tool makes it.

---

## 6. Give the answer a shape

A read answers a shape or an array of them, detached from the database. If a piece currently
returns a record, a hash, or `nil`-or-a-record, that is where the shape goes — one class, its
fields asserted, holding parts nested rather than flattened.

**Check:** the `Read` base class refuses anything that is not a `Shape`, at the door.

---

## 7. Stop when the count stops falling

```sh
shipshape check
```

The ratchet is the stopping condition: the count must fall and never rise. That is what makes
this safe to do in slices — the half-finished state is legal, and the next slice starts from
a floor.

---

## What this leaves you

**One class per act, each named for what it does.** "What can happen to a booking" is answered
by listing a directory, every entry carries its own permission because a permission is the
class name, and a new case has nowhere to go but a new class — there is no branch to grow.

## What none of this proves

**Nothing here shows the code still works.** `shipshape check` proves the offence count fell.
Split a service into six operations and every check goes green whether or not the behaviour
survived.

So: `shipshape next` offers files a test names before the rest, and the honest sequence is to
write the characterisation test **first** — call the method, record what it answers, pin it —
and only then split. A file nothing tests is a file to leave until something does.
