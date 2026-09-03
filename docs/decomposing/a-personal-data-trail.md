# Following a personal data trail — making erasure possible before it is asked for

A procedure, meant to be followed by an agent one step at a time. Every step ends with
something to **run**, because a decomposition nobody can verify is a rewrite with extra
confidence.

**What you are aiming at:**

```ruby
# every column holding something about a person is declared, once, in code
COLUMNS = {
  "users" => { "email" => :anonymise, "country_code" => :not_personal },
}.freeze

# and erasure is a sequence somebody can read
class ForgetPerson < Workflow
  def call
    AnonymiseComments.call(actor: actor, person_id: @id)
    DeleteSessions.call(actor: actor, person_id: @id)
    AnonymiseUser.call(actor: actor, person_id: @id)
  end
end
```

Erasure is unimplementable without an inventory — you cannot delete what nobody can enumerate.
The declaration is what makes the workflow writable, and it is the deliverable of step 0.

**This one has a stronger warning than the others.** Every step here makes erasure *more
possible*; none of them makes an application lawful, and the two are easy to confuse when a
build goes green. If somebody reads the output of this procedure as legal assurance, the
procedure has done harm. Say what it checked, and say the rest is unexamined.

---

## 0. Accept that the repository is a fraction

Before anything: write down where personal data lives that this procedure will never see.

- application logs, and how long they are kept
- database backups, and their retention
- the analytics pipeline and the warehouse
- every third party the data was sent to — each one is a copy you owe erasure on
- exports somebody generated and left in a bucket

**This list is the deliverable of step 0**, and it is usually longer than the schema. A tool
that inspects `app/` and `db/` sees one of these and reports on it; the honest sentence at the
end of this work is "the database is inventoried, and the rest is not".

**Check:** the list exists and somebody who was not you has read it.

---

## 1. Take the inventory the cheap way

```sh
shipshape check --only Shipshape/PersonalDataIsDeclared
```

Every column whose name suggests a person, that nothing has classified. Four answers, and
picking one is the whole task:

| Route | When |
|---|---|
| `:delete_row` | the row is about the person and goes with them |
| `:anonymise` | the row must survive — an order, a comment thread — and the field must not |
| `:retain_with_reason` | a statutory hold. **Write the reason in a comment; it is the only record of why** |
| `:not_personal` | it matched the name and is not about a person |

Do this in one pass, table by table, with somebody who knows the domain. **It is an hour of
work once and archaeology forever if skipped** — and the person who knows what `legacy_ref`
holds is usually still reachable today and will not be in two years.

**Check:** the cop is silent, and `PersonalData.tables_needing_erasure` prints a list you
recognise.

---

## 2. Find the fields the name does not give away

The cop matches names. It will not find `contact_ref`, `handle`, `party_key`, `notes`, or a
`jsonb` blob with a person inside it — and those are where the interesting data is, because a
field named `email` was obvious to everybody including whoever wrote the retention policy.

```sh
grep -rn "jsonb\|text \"notes\"\|serialize" db/schema.rb
```

Add what you find to `Names` in the cop's config, so the next column named that way is caught
rather than remembered.

**Check:** you extended `Names` at least once. If you did not, the schema is unusually plain
or the search was not real.

---

## 3. Decide what happens to the children

```sh
shipshape check --only Shipshape/AssociationsSurviveErasure
```

An association with no `dependent:` leaves the children behind — the person is deleted and
everything they wrote still carries their name.

**`:destroy` is usually the wrong answer** and reaching for it to clear the offence is the
failure mode of this step. A comment thread with holes in it is worse than one with an
anonymous author; an invoice that vanishes is a financial record that vanished. The common
correct shape is **the row survives and the personal columns are anonymised** — which is not a
`dependent:` option at all, so:

```ruby
has_many :comments, dependent: :restrict_with_error
```

and the anonymisation is a command, called before the delete, named for what it does.

**Check:** the cop is silent, and for each `:destroy` you can say why the child should not
outlive the parent.

---

## 4. Turn the nullable foreign keys into rows

A nullable `user_id` is an erasure bug wearing a schema decision. "Sometimes nobody" means
erasure has to find and clear it, in code somebody remembered to write — and a column that was
never cleared looks exactly like one that was always empty.

[a nullable column](a-nullable-column.md) is the procedure; the erasure angle is the reason to
run it here. A join row is deleted and *gone*; a nullable column is a thing to remember.

**Check:** `AbsenceIsAbsenceNeverAValue` names no foreign key on a table in
`PersonalData.tables_needing_erasure`.

---

## 5. Write the erasure as operations, not as a script

The inventory is now a work list. Each table with `:delete_row` or `:anonymise` gets its part
in a command, and a workflow sequences them:

```ruby
class ForgetPerson < Workflow
  def call
    AnonymiseComments.call(actor: actor, person_id: @id)
    DeleteSessions.call(actor: actor, person_id: @id)
    AnonymiseUser.call(actor: actor, person_id: @id)
  end
end
```

**Every step must be idempotent**, and here that is not a nicety: an erasure that half-ran and
cannot be re-run safely is the worst state available — the request is recorded as handled and
the data is still there. A workflow spans transactions, so this is the same obligation
[a query that writes](a-query-that-writes.md) and [inline IO](inline-io.md) describe, with a
worse failure.

**Check:** run the workflow twice against a fixture. The second run changes nothing and
raises nothing.

---

## 6. Count the copies you send out

```sh
shipshape check --only Shipshape/IoIsItsOwnKind
```

Every crossing is a place personal data may have left. Once the IO is its own kind, the
question "who did we send this to" has an answer that is a list of classes rather than a grep
— which is the erasure request you cannot answer from the database at all, because the data is
not in it.

**Check:** for each `io_command`, you can say whether personal data is in the payload, and if
it is, what that vendor's deletion route is.

---

## What this leaves you

**An inventory that makes erasure writable.** "Where is this person's data" has an answer in
code rather than in somebody's memory, and the answer is checked against the database on every
run — so a column added next year fails the build until somebody classifies it.

## What none of this proves

**Nothing here shows you are lawful, and nothing here shows the data is gone.**

The checks prove: every name-matching column has been classified, every association has a
decision, the registry matches the live database. They do not prove the classification is
right, that an `:anonymise` route has anything implementing it, that a hash was not reversible
because somebody kept the key, or that the fourteen other places the data lives were touched.

The one test that means something is the end-to-end one: **take a fixture person, run the
erasure, and go looking for them** — in the database, in the logs, in the search index, in the
warehouse, in every vendor. What you find is the real report. Everything above only makes that
test possible to write.
