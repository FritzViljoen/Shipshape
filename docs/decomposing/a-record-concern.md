# Decomposing a record concern — a module that obliges a table

A procedure, meant to be followed by an agent one step at a time. Every step ends with
something to **run**, because a decomposition nobody can verify is a rewrite with extra
confidence.

The shape: `app/models/concerns/sluggable.rb`, forty lines, included by twenty-two models —
and every one of their tables carries `slug` and `slug_generated_at`. The module is small.
The obligation it creates is written into twenty-two `CREATE TABLE`s, and nothing states it.

---

## It is a side effect of assuming one model is one table

**With that assumption there is nowhere for a shared fact to live except on every table that
shares it.** A concern is the only tool Rails offers for "these twenty-two things all have a
slug", and because a model *is* a table, saying it in a module says it in twenty-two schemas.
The module looks like code reuse. It is schema duplication with an `include` in front.

Drop the assumption and the fact has an obvious home: **a slug is a thing, and things have
tables.** One `slugs` table, keyed by what it belongs to, and the twenty-two tables go back to
holding what they are about.

**What you are aiming at:**

```ruby
# before — twenty-two tables each carrying slug and slug_generated_at
class Story < ApplicationRecord
  include Sluggable
end

# after — one table for the thing, and the twenty-two hold what they are about
class SlugRecord < ApplicationRecord
  belongs_to :sluggable, polymorphic: false   # one column per owner, not a type string
end

AssignSlug.call(actor: actor, story_id: id)   # the act that used to be a callback
```

This is the same reading [a god record](a-god-record.md) applies to one class — the columns
are several things sharing a table — applied to one module across many. **A record concern is
a god record distributed**, and it is harder to see for exactly that reason: the god record is
a 4,000-line file that everybody complains about, and this is twenty-two files that each look
reasonable, plus a module nobody reads as schema.

`Shipshape/PersistenceHoldsNoBehaviour` says so in its own stated limit — it sees "the record
tree only", and "a module included from outside … is not covered". The cop reads the record;
the concern is not in it. That is why this needs a procedure and not a cop.

---

## 0. List the includers next to their columns

```sh
grep -rln "include Sluggable" app/models
```

Then read the column sets for those tables out of `db/schema.rb` and put them side by side.
The comparison is the finding, and it has three answers in it:

- columns present on **every** includer — what the concern actually obliges
- columns present on **some** — includers carrying a column they never populate
- a column the module **reads** that an includer does not have — a `NoMethodError` waiting for
  the one code path that reaches it

**Check:** you can write the concern's implied column list, and name which tables do not
satisfy it. If every includer has every column, the obligation is real and step 2 is the
work; if they differ, the module is already two modules.

---

## 1. The implied contract is the defect, not the sharing

Nothing declares that including `Sluggable` obliges your table to have `slug`. Not the module,
not the model, not the schema. The obligation exists, it is enforced by nothing, and it is
discovered when a request reaches the one model that missed the migration.

**Sharing behaviour is fine. Obliging a schema silently is not.** Keep that distinction: this
procedure is not an argument against modules, and a concern that touches no column is a
[shared concern](a-shared-concern.md) and belongs to that procedure instead.

**Check:** you can state the contract in one sentence — "including this requires columns X, Y"
— and confirm no file in the repository says it.

---

## 2. The columns arrive nullable, and that is the mechanism

A concern included by twenty-two models cannot demand its columns be populated: the model that
includes it tomorrow has no value for them yet. So they ship nullable, twenty-two times.

**One include is one nullable column per table**, which makes this shape a large and
self-renewing source of the category [a nullable column](a-nullable-column.md) describes, and
it renews faster than that procedure can drain it —
[`no-nullable-columns`](../laws/no-nullable-columns.md) is fighting the symptom while the
concern keeps producing them.

**Check:** count the nullable columns the concern is responsible for. That number is the cost
of leaving it as it is, and it grows with the next includer.

---

## 3. Three answers, and only one of them stays a module

| What the columns are | What they become |
|---|---|
| a thing the record **sometimes has** | its own table, joined — absence is a missing row, not a NULL |
| a thing **every** includer genuinely has | columns on each table, `NOT NULL`, declared per model; the module keeps behaviour or dies |
| a thing **only some** includers use | two concerns, split by column set rather than by method name |

**The first is the one that gets missed, and it is the one worth the effort.** `Sluggable` with
`slug`, `slug_generated_at` and four methods over them is not a mixin — it is a `Slug` that
nobody has written yet, and every includer is carrying its fields flattened. That is
[`a-shape-is-composed-not-flattened`](../laws/a-shape-is-composed-not-flattened.md) arriving as
a module instead of as columns.

**Check:** none. This is the judgement the procedure exists to leave room for.

---

## 4. Take the behaviour off before the columns

A concern that adds columns almost always adds callbacks over them —
`before_save :generate_slug` is the whole reason it was a concern and not a migration. Move
that first, while the columns are still where the code expects them:
[a callback web](a-callback-web.md) is the procedure, and
[`no-lifecycle-callbacks`](../laws/no-lifecycle-callbacks.md) is the law.

**Do not move columns under live callbacks.** The callback fires on save, the column moved, and
the failure is a write that silently stops happening rather than an error.

**Check:** `Shipshape/NoCallbacks` is silent on the includers, and the module defines no
callback.

---

## 5. Move one includer, not the concern

The trap is rewriting the module and migrating twenty-two tables in one change. Take the
includer with the best tests — `shipshape next` ranks by coverage — and give it the new shape
while the other twenty-one keep the module. Both shapes coexist; the concern shrinks by one
includer at a time.

**Check:** after each includer, its edge tests still pass
([characterise the edges](characterise-the-edges.md) first, as everywhere), and the includer
list from step 0 is one shorter.

---

## 6. Stop when the count stops falling

```sh
shipshape check
```

---

## What this leaves you

**The schema states its own obligations.** A table's columns are about the thing the table is
about, a shared fact lives in the table that owns it, and adding a model no longer means
remembering which four migrations a module implies.

## What none of this proves

**Nothing here shows the includers still work.** The reliable failure is a scope or a query
elsewhere that read the column directly — `Story.where.not(slug: nil)` — which compiles fine
against the old schema and returns the wrong rows against the new one. Those are found by
[a call-site sweep](a-call-site-sweep.md), and the cop cannot see them because they name a
column and not a class.

**And the join is not free.** Moving `slug` to a `slugs` table turns one column read into a
join, and a list page that read it per row now needs an include. That cost is real, it is
sometimes the reason not to do this, and it should be measured rather than argued about.
