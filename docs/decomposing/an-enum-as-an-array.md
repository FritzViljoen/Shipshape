# Decomposing an enum stored as a position — the meaning is the index

A procedure, meant to be followed by an agent one step at a time. Every step ends with
something to **run**, because a decomposition nobody can verify is a rewrite with extra
confidence.

```ruby
enum channel: %i[web phone api]
```

The column holds `0`, `1`, `2`. **The meaning of every row is its position in a Ruby array**,
and the array is in a file that anybody may reorder.

Insert `:partner` at the front and every `web` order becomes `partner`, every `phone` becomes
`web`, silently, with no migration, no error, and no way to notice except by reading rows. A
reorder is a data migration that does not look like one.

---

## 0. First: does the column deserve to exist?

**Do not start here with a `status` column.** A status is almost always a denormalisation of
events that already happened — `delivered` means a delivery row exists — and
[a state machine](a-state-machine.md) is the procedure for it. Fixing how such a column is
*stored* is careful work on a column that should be deleted, and it makes the wrong shape
harder to remove by making it tidier.

This procedure is for an enum that is a **recorded fact**:

| A real enum | Why |
|---|---|
| `channel` — how the order arrived | a fact about the past. Nothing else in the database implies it, and it never changes |
| `unit` — grams or kilograms | a property of this row, not a summary of other rows |
| `severity` — recorded when the entry was written | the same |

**Do not classify it by asking whether the data agrees with its source.** A snapshot disagrees
with its source on purpose, and a denormalisation disagrees by drifting — identical evidence,
opposite verdicts. [a stored derivation](a-stored-derivation.md) sorts the four cases by why
the write happens, and it is the step before this one whenever the answer is not obvious.

**Check:** for each enum you found, you can name the fact it records and say what would
contradict it. "Nothing" is the answer that lets you continue.

---

## Two defects, and the second is the worse one

**The meaning lives outside the database.** A row's channel cannot be read without the current
version of the application source. Every report, every psql session, every replica consumer,
every analyst sees integers.

**And `0` is both the first value and the default of an empty integer column.** So "nobody has
said" and "web" are the same byte. That is
[`no-nullable-columns`](../laws/no-nullable-columns.md) arriving through a door it does not
cover: the column need not be nullable at all to lose the distinction, because the zero is
doing two jobs and the law only reads whether NULL is admitted.

---

## 1. Find them, and find the ones already at risk

```sh
grep -rn "enum .*: *%[iw]\[\|enum .*: *\[" app
```

An `enum` given an **array** is positional. An `enum` given a **hash** is not — `enum channel:
{ web: 0, phone: 1 }` at least names its numbers, and is a smaller version of the same problem.

Then ask the data what is actually in use:

```sql
SELECT channel, COUNT(*) FROM orders GROUP BY 1 ORDER BY 1;
```

**A value in the data with no name in the array is the finding.** It means the array already
shrank, or already got reordered, and rows are sitting on positions the code no longer maps.

**Check:** for each enum, the set of integers in the data and the set of positions in the code
are the same set. Where they differ, stop and find out what happened before changing anything.

---

## 2. Pin the current mapping before touching the array

The first change is not the fix. It is making the existing meaning explicit, so that the fix
cannot move it:

```ruby
# no behaviour change: the same integers, now written down
enum channel: { web: 0, phone: 1, api: 2 }
```

**This is safe and it is the step people skip.** After it, reordering the source is harmless,
which means every later step can be reviewed without anybody having to hold the array order in
their head.

**Check:** the mapping in the code matches the `GROUP BY` from step 1, value for value, and the
suite is green with no other change in the commit.

---

## 3. Move to strings, so the column says what it means

```ruby
# the column is a string; the row reads `"phone"` in psql, in a report, on a replica
enum channel: { web: "web", phone: "phone", api: "api" }
```

The migration is the ordinary dual-write shape — add the column, write both, backfill, verify,
move readers, drop the old one — set out in [a serialized column](a-serialized-column.md),
step 3.

```sql
-- the verification, before any reader moves
SELECT COUNT(*) FROM orders WHERE channel_name IS DISTINCT FROM
  (ARRAY['web','phone','api'])[channel + 1];
```

**Check:** zero, on production-shaped data.

---

## 4. Constrain the column, now that the values are words

A string column accepts every string. The set is closed in Ruby and open in the database, which
is the same defect this procedure started with, mirrored.

- a `CHECK` constraint listing the values, or
- a lookup table with a foreign key

**Check:** an `UPDATE` setting an unlisted value is refused by the database, not by a
validation. Run it and watch it fail — a constraint nobody has seen reject anything is a
constraint nobody has confirmed exists.

---

## 5. Stop when the database can be read on its own

```sh
shipshape check
```

---

## What this leaves you

**A row that means the same thing to everyone reading it**, including the people who are not
running your code: a psql session, a BI tool, a replica consumer, an incident at 3am.

## What none of this proves

**A reorder that already happened is invisible to all of this.** If the array was reordered in
2023 and nobody noticed, the rows written before it hold the old meaning and the rows after it
hold the new one, and both are the same integers. No query distinguishes them; only the git
history of the enum line does. Look there before trusting step 2's mapping:

```sh
git log -p -S "enum channel" -- app/models/order.rb
```

**And `enum` generates methods** — `order.phone?`, `Order.phone` — which is
`code-is-written-not-generated` under an exemption for framework macros. This procedure changes
what is stored; it does not remove the generated interface, and moving off `enum` entirely is a
larger change than this one.
