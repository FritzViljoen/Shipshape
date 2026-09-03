# Decomposing a concern nobody modelled — several nullable columns are one event

A procedure, meant to be followed by an agent one step at a time. Every step ends with
something to **run**, because a decomposition nobody can verify is a rewrite with extra
confidence.

**What you are aiming at:**

```ruby
# before — three columns, three nullable states, and no name for what they mean together
t.datetime "cancelled_at"
t.string   "cancellation_reason"
t.integer  "cancelled_by_id"

# after — the event has a table, and a row is the fact
create_table "cancellations" do |t|
  t.references :booking, null: false, foreign_key: true, index: {unique: true}
  t.string     :reason, null: false
  t.references :cancelled_by, null: false, foreign_key: {to_table: :users}
  t.timestamps
end
```

```ruby
CancelBooking.call(actor: actor, booking_id: id, reason: reason)   # one deed, one row
```

`bookings.cancelled_reason` being NULL for every non-cancelled booking already says there is a
`Cancellation` — [`a-nullable-column.md`](a-nullable-column.md) names that sentence. What it
does not walk is what happens when the sentence is true of three columns at once, and an agent
fixes each one on its own: `booking_suppliers` for the linkage, `cancellation_reasons` for the
text, `cancellation_actors` for who did it. Three tables, three commands to write them, three
queries to read them back — the CRUD explosion this canon exists to stop, arriving one
`null: true` at a time. [`absence-is-absence-never-a-value`](../laws/absence-is-absence-never-a-value.md)
says it plainly: **"the failure is a concern nobody modelled; the null is only what that looks
like in a column."** This procedure is the modelling act the law names and does not walk.

**Where this sits between the two neighbouring procedures:** [`a-nullable-column.md`](a-nullable-column.md)
is for one column that turns out to want a table of its own. [`a-god-record.md`](a-god-record.md)
is for a table so overloaded it needs several new shapes and probably a split. This one is for
the case in between: a handful of nullable columns on one table that are one concern wearing
several names. If you opened this page for a single column, go there instead; if the table
also shows a flag cluster, a status pair, and a satellite neighbour or two beyond the cluster
you are looking at, this is smaller than what you have — go to `a-god-record.md`.

---

## 0. Make the table visible

```sh
shipshape tables --table <name>
```

Read the signals as `TableShapes` reports them: nullable columns, migration-blind columns,
boolean columns, status-shaped columns, blank-sentinel-capable columns, and the four
neighbour shapes. **None of this is a verdict.** The tool reads the schema and proposes
nothing; grouping the columns into a concern is the step that follows, and it is yours.

**Check:** you can read off the nullable-column list for this table from the output.

---

## 1. Cluster by co-nullity — this is a data question, not a schema one

`shipshape tables` cannot answer this: it reads `db/schema.rb`, never a row. Ask the table
itself which nullable columns are null on the same rows and present on the same rows:

```sql
SELECT
  COUNT(*) FILTER (WHERE cancelled_at IS NOT NULL)          AS at_set,
  COUNT(*) FILTER (WHERE cancellation_reason IS NOT NULL)   AS reason_set,
  COUNT(*) FILTER (WHERE cancelled_by_id IS NOT NULL)       AS by_set,
  COUNT(*) FILTER (WHERE cancelled_at IS NOT NULL
                     AND cancellation_reason IS NOT NULL
                     AND cancelled_by_id IS NOT NULL)        AS all_three_set,
  COUNT(*)                                                   AS total
FROM bookings;
```

Two columns belong to one cluster when their individual `_set` counts equal the joint count:
every row where one is present, all of them are. That is co-nullity, and it is the strongest
signal in this whole procedure, because it is the only one that reads the data rather than
guessing from names.

**What this query establishes, and what it does not:**

- It establishes that on this table, today, these columns are present or absent together.
- **It does not establish that they mean one thing.** A small table, or one with low
  cardinality on the columns involved, can pass this query by coincidence — three columns
  that happen to be set on the same twelve rows out of twelve is not evidence of anything.
- It does not establish the link is permanent. It answers for the rows that exist, not for a
  constraint the schema currently enforces.

Run it once more grouped by whatever else distinguishes the rows — a status or type column —
because a cluster that only holds within one status value is a narrower claim than "always
together," and worth knowing before you extract.

**Check:** for every pair in the candidate cluster, the two `_set` counts and the joint count
agree, or you can say in one sentence why the disagreement is expected.

---

## 2. Corroborate with the weaker, schema-visible signals

Co-nullity is the only one that reads rows; these three read code and are weaker for it —
each catches a concern the query above misses, and each can also mislead on its own:

- **A shared name stem.** `cancelled_*` is visible without a query, and it misses a concern
  whose columns were named inconsistently before anyone saw them as one thing.
- **One operation touching all of them.** Grep for every column in the candidate cluster and
  see whether the same command or query reaches all of them:

  ```sh
  grep -rln "cancelled_at\|cancellation_reason\|cancelled_by_id" app lib | grep -v spec
  ```

- **A status column whose value gates them.** `state: "cancelled"` implying the cancellation
  columns are populated is [`a-state-machine.md`](a-state-machine.md)'s territory arriving
  from the column side — the state is denormalising the same event this cluster is hiding.

**Check:** every column in the candidate cluster appears in the same grep hits as the others,
or you can name which caller is the exception and why it only touches one.

---

## 3. Name the cluster as a thing, not as fields

"A cancellation." "A confirmation." An event that happened, or a fact that became true — not
"the cancelled-at group" and not a list of three column names.

**If it will not take that name, it is probably not a concern yet, and that is a finding, not
a failure.** Stop here rather than extracting three columns that merely happen to correlate;
write down what you found instead.

**Check:** you can complete the sentence "a `<name>` is true when …" using only the columns in
the cluster, with nothing left over and nothing missing.

---

## 4. Apply the unlock test before writing a migration

Reuse [`a-nullable-column.md`](a-nullable-column.md#0-model-the-table-before-you-fix-the-column)'s
test rather than a second one: an extraction earns its place by unlocking a sentence the old
shape could not say. `shipshape tables` names the same four shapes for a foreign-key
neighbour once you sketch the new table — a cluster extraction is almost always the second
one, **unlocked a composite fact**: several `NOT NULL` columns behind one unique key, which is
new information the three separate nullable columns could not state. **Unlocked nothing means
stop** — a satellite with a unique key back and one still-nullable column is the same dodge
`a-nullable-column.md` names, arrived at with a cluster instead of a single column.

**Check:** you can name which of the four shapes the extraction is, in one sentence, before
the migration is written.

---

## 5. Extract the whole cluster at once

```ruby
create_table "cancellations" do |t|
  t.references :booking, null: false, foreign_key: true, index: {unique: true}
  t.string     :reason, null: false
  t.references :cancelled_by, null: false, foreign_key: {to_table: :users}
  t.timestamps
end
```

Every column in the new table is `NOT NULL`. Absence of the event is the absence of the row —
not one nullable column left behind to mark "not yet," which would only move the gap one
table over and leave the other two columns stranded on the original table.

Migrate in the same four-deploy order [`a-nullable-column.md`](a-nullable-column.md#5-migrate-in-the-order-that-stays-green)
gives — add, backfill, switch reads then writes, drop — applied to the whole cluster as one
unit. Splitting the cluster's columns across separate migrations reopens the exact miscount
this procedure exists to close: three small, separately-landed changes read as three
problems solved, not one concern found.

**Check:** `shipshape tables --table <name>` no longer lists any column from the cluster as
nullable, and the new table's own listing shows none either.

---

## 6. The operations follow the concern, not the columns

This is the step the single-column procedure has no need for, because one column never tempts
anyone into three commands. A cluster does:

```ruby
# wrong — the CRUD explosion, one command per field
SetCancelledAt.call(booking_id: id, at: now)
SetCancellationReason.call(booking_id: id, reason: reason)
SetCancelledBy.call(booking_id: id, actor_id: actor.id)
```

```ruby
# right — one deed, one row
CancelBooking.call(actor: actor, booking_id: id, reason: reason)
```

[`one-operation-one-class`](../laws/one-operation-one-class.md)'s sizing test is the reason:
"who is allowed to do it" is one question here, one actor, one permission, so it is one
operation. Three commands writing three columns of one event either check that permission
three times or, more likely, stop checking it at all past the first — and a reader who has
just named a clean concern is exactly the person about to write the three commands, because
each column now looks like its own small, obviously-correct change.

**Check:**

```sh
grep -rn "cancelled_at\s*=\|cancellation_reason\s*=\|cancelled_by_id\s*=" app lib
```

names one command, or a workflow calling it — not three call sites each setting one column —
and `shipshape check` still falls.

---

## What this leaves you

**A question with one place to be answered, and a fact with one row to hold it.** "Why was
this cancelled?" is a row, with a reason and an actor, instead of three nullable columns that
happen to agree — and the next person who needs a fourth fact about the cancellation adds a
column to `cancellations`, not a fourth nullable column to `bookings`.

## What none of this proves

**Co-nullity is evidence, not proof.** It can hold by coincidence on a small or
low-cardinality table, and it says nothing about whether the columns will keep moving
together as the table grows. Nor does naming the cluster prove the naming is finished: a
fourth column added next quarter "because it's related" to an already-extracted concern is a
sign that either the cluster was named too narrowly the first time, or a second concern is
starting to share the new table the way the first one shared `bookings` — the same failure,
one column later, and this procedure has no step that catches it happening again.
