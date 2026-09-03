# Decomposing a nullable column — a gap is not a value

A procedure, meant to be followed by an agent one step at a time. Every step ends with
something to **run**, because a decomposition nobody can verify is a rewrite with extra
confidence.

**What you are aiming at:**

```ruby
# before — the column says "sometimes nobody", and every reader must remember
add_column :bookings, :supplier_id, :integer, null: true

# after — the absence of a row IS the absence, and the column cannot be empty
create_table :booking_suppliers do |t|
  t.references :booking, null: false, foreign_key: true, index: {unique: true}
  t.references :supplier, null: false, foreign_key: true
end
```

The unique index is half the fix: without it the join holds two answers to one question. Where
the null meant "use the default", the domain names the fallback in one place instead.

The shape is in `db/schema.rb` rather than in a class, which is why it is the category most
often missed: a run over `app/` never sees it.

```ruby
t.string  "tier",          default: "standard"
t.integer "supplier_id"                          # nullable
t.boolean "active",        default: true
```

**Every meaning given to NULL is a fact no type states.** "Inherit the default", "off", "not
linked yet", "we never asked" — the column says none of them, so each reader invents one, and
two readers inventing differently is a bug nothing can catch.

---

## 0. Model the table before you fix the column

```sh
shipshape tables --table bookings
```

`AbsenceIsAbsenceNeverAValue` reports one column at a time. Ten small fixes on one table read as ten
small problems, and each gets its own join table keyed back to the same parent — zero nulls,
ten satellites, and the table underneath is the same size, now harder to see. Read every
signal on the whole table before deciding what one column needs.

**If the table shows a flag cluster, a status pair, several nullable columns, and a
satellite-shaped neighbour or two, stop here** — [a god record](a-god-record.md) is what the
columns are showing, at their own scale, and fixing one column first only buries it deeper.

**An extraction earns its place by unlocking a sentence the old shape could not say.**
Splitting off channels unlocked *two phone numbers*; an `engagement_closure` table unlocked
"closed, with a reason, at a time, by someone." A `tenant_branding` satellite shipped with one
still-nullable `logo_url` unlocked nothing — the null just moved house, and `shipshape tables`
names exactly this shape: a unique key back plus a single nullable column. That is the same
god-record question as above, arriving one column at a time — if it recurs across a table's
satellites, [go there](a-god-record.md) instead of writing a fix for each.

**The fix and the dodge differ by exactly one `null: false`.** `booking_suppliers` in the
example above — a unique key back to `bookings`, and one required `supplier_id` beside it —
is `shipshape tables`' fourth shape: it unlocked *"linked to exactly one supplier, or not
linked at all,"* with no null anywhere. Drop that one `null: false` and the same table has
unlocked nothing: the supplier is still sometimes absent, just absent one table over.

**Check:** before writing the migration, you can say in one sentence what the new shape lets
you say that the old one could not — and the sentence names more than "not null now".

---

## 1. Look where the other procedures do not

```sh
shipshape report
```

`AbsenceIsAbsenceNeverAValue` and `NoColumnDefaults` read `db/schema.rb`. A `shipshape next` run scoped
to `app/` reports nothing about either — **not because the schema is clean, but because it was
not inspected**, which reads identically.

**Check:** the report names a count for both, and the count is not "no schema found".

---

## 2. Sort the nullable columns — four shapes, four answers

| What the NULL means | What it becomes |
|---|---|
| "nobody has said yet" on a **foreign key** | a join table with a unique index |
| "nobody has said yet" on a **value** | NOT NULL plus an explicit `_at`/`_by` companion, or a join |
| "this kind of row does not have one" | **two kinds of thing in one table** — split it |
| "the default applies" | NOT NULL, and the fallback is named in the domain |

**The third is the one worth finding.** A column that is NULL for exactly the rows of one type
is not a gap; it is a second table that has not been written. `bookings.cancelled_reason`
being NULL for every non-cancelled booking says there is a `Cancellation`.

**Check:** for each nullable column you can say which of the four it is, in words, before
writing a migration.

---

## 3. A nullable foreign key is almost always a join

This is the near-universal answer for a foreign key, and it does two things at once:

```ruby
# before
t.integer "supplier_id"           # NULL until somebody links one

# after
create_table "booking_suppliers" do |t|
  t.references :booking, null: false
  t.references :supplier, null: false
  t.index [:booking_id], unique: true      # <- half the fix, and not optional
end
```

**The unique index is half of it.** Without it the join holds two answers to one question,
which is a worse problem than the NULL was — and it is the half that gets forgotten, because
the table looks finished without it.

To say "nobody has said", you do not store a row. That is the whole point: absence is the
absence of a row, which is a fact the schema states rather than a value somebody interprets.

**A nullable foreign key also tends to hide the third shape above** — two kinds of thing
sharing a table. Check for that before reaching for the join.

**Before creating it, ask what [modelling the table first](#0-model-the-table-before-you-fix-the-column)
already asked:** does the join let you say something the old column could not? `booking_suppliers`
above says "linked, to exactly one supplier, or not at all" — that is new. A join that ends up
with one unique key back and one nullable column beside it has said nothing new; [a god
record](a-god-record.md) is the same question, arriving one column at a time.

**Check:** the index is in `db/schema.rb`, and `AbsenceIsAbsenceNeverAValue` no longer names the column.

---

## 4. A column default is a second declaration of the same fact

```ruby
t.string "tier", default: "standard"
```

The column now says the fallback and the domain says the fallback, and **they drift** — the
column's copy is the one nobody updates, because changing it needs a migration and changing
the domain needs an edit.

The column refuses the gap; the domain names the fallback:

```ruby
def tier
  @tier ||= Tier.standard        # one place, greppable, testable
end
```

**Watch for the default that is load-bearing.** `default: true` on a boolean added to a table
with existing rows was doing the backfill. Removing it needs the backfill written out — which
is the point: it was a migration disguised as a schema line, and it ran once, invisibly.

**Check:** `NoColumnDefaults` is silent, and one place in the domain names each fallback.

---

## 5. Migrate in the order that stays green

For each column, four deploys, and they are separate on purpose:

1. **add** the new structure — the join table, or the companion column, nullable for now
2. **backfill** — a forever-command, idempotent, run repeatedly until it finds nothing
3. **switch reads** to the new structure, writes to both
4. **drop** the old column and add `null: false`

Steps 2 and 4 are where this goes wrong. **A backfill that is not idempotent cannot be
re-run**, and it will need re-running — the first pass always misses rows written while it ran.
**`null: false` before the backfill completes** takes the table down on the next insert.

**Check:** after step 2, running the backfill twice changes nothing the second time. That is
the test, and it is worth writing before the backfill.

---

## 6. Do not batch this

One column per change. The temptation is a single migration that fixes forty columns, and it
is wrong for a reason specific to this work: **each column is a different one of the four
shapes above**, and a batch hides which judgement was made about which.

`shipshape check` is a ratchet, so a partial state is legal. Forty small changes each land
green; one big one lands or does not.

**Check:** `shipshape check` — the count falls and never rises.

---

## What this leaves you

**A schema where absence is the absence of a row.** Every column means one thing, no reader has
to remember which of four meanings a null carried here, and the database refuses the state
nobody wanted rather than trusting each writer to avoid it.

## What none of this proves

**Nothing here shows the NULLs meant what you decided they meant.** The schema records that a
value was absent; it never records why, and the person who knew has usually left. Every check
in this procedure passes on a wrong reading — a column you split into a join because you
thought it meant "not linked yet", when it actually meant "this row is a different kind of
thing", is now a join table that is empty for half the rows and nothing objects.

The only real evidence is the data. Before deciding, count:

```sql
SELECT COUNT(*) FILTER (WHERE supplier_id IS NULL), COUNT(*) FROM bookings;
```

and then the same grouped by whatever else distinguishes those rows. **If the NULLs correlate
with a status, a type, or a date range, it is the third shape** — two kinds of thing in one
table — and no amount of schema work fixes that until the table is split.
