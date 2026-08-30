# Decomposing an enum stored as a position — the meaning is the index

A procedure, meant to be followed by an agent one step at a time. Every step ends with
something to **run**, because a decomposition nobody can verify is a rewrite with extra
confidence.

```ruby
enum status: %i[draft live archived]
```

The column holds `0`, `1`, `2`. **The meaning of every row is its position in a Ruby array**,
and the array is in a file that anybody may reorder.

Insert `:pending` at the front and every `draft` row in the database becomes `pending`, every
`live` becomes `draft`, silently, with no migration, no error, and no way to notice except by
reading rows. A reorder is a data migration that does not look like one.

---

## Two defects, and the second is the worse one

**The meaning lives outside the database.** A row's status cannot be read without the current
version of the application source. Every report, every psql session, every replica consumer,
every analyst sees integers.

**And `0` is both the first value and the default of an empty integer column.** So "nobody has
said" and "draft" are the same byte. That is
[`no-nullable-columns`](../laws/no-nullable-columns.md) arriving through a door it does not
cover: the column need not be nullable at all to lose the distinction, because the zero is
doing two jobs and the law only reads whether NULL is admitted.

---

## 0. Find them, and find the ones already at risk

```sh
grep -rn "enum .*: *%[iw]\[\|enum .*: *\[" app
```

An `enum` given an **array** is positional. An `enum` given a **hash** is not — `enum status:
{ draft: 0, live: 1 }` at least names its numbers, and is a smaller version of the same
problem.

Then ask the data what is actually in use:

```sql
SELECT status, COUNT(*) FROM stories GROUP BY 1 ORDER BY 1;
```

**A value in the data with no name in the array is the finding.** It means the array already
shrank, or already got reordered, and rows are sitting on positions the code no longer maps.

**Check:** for each enum, the set of integers in the data and the set of positions in the code
are the same set. Where they differ, stop and find out what happened before changing anything.

---

## 1. Pin the current mapping before touching the array

The first change is not the fix. It is making the existing meaning explicit, so that the fix
cannot move it:

```ruby
# no behaviour change: the same integers, now written down
enum status: { draft: 0, live: 1, archived: 2 }
```

**This is safe and it is the step people skip.** After it, reordering the source is harmless,
which means every later step can be reviewed without anybody having to hold the array order in
their head.

**Check:** the mapping in the code matches the `GROUP BY` from step 0, value for value, and the
suite is green with no other change in the commit.

---

## 2. Move to strings, so the column says what it means

```ruby
# the column is a string; the row reads `"archived"` in psql, in a report, on a replica
enum status: { draft: "draft", live: "live", archived: "archived" }
```

The migration is the ordinary dual-write shape — add the column, write both, backfill, verify,
move readers, drop the old one — set out in [a serialized column](a-serialized-column.md),
step 3.

```sql
-- the verification, before any reader moves
SELECT COUNT(*) FROM stories WHERE status_string IS DISTINCT FROM
  (ARRAY['draft','live','archived'])[status + 1];
```

**Check:** zero, on production-shaped data.

---

## 3. Ask whether it is a state, because then it is not an enum

An enum is a closed set of names. If the values have **transitions** — draft becomes live,
live becomes archived, archived becomes nothing — the set is not the interesting part and
naming the values is not the work.

That is [a state machine](a-state-machine.md), and the enum is how it is currently
spelled. Do steps 0 to 2 first regardless: a state machine over positional integers is the
same corruption with more branches attached.

**Check:** you can say whether this is a set of labels or a set of states, and the answer
decides whether the next procedure is this one or that one.

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
history of the enum line does. Look there before trusting step 1's mapping:

```sh
git log -p -S "enum status" -- app/models/story.rb
```

**And `enum` generates methods** — `story.live?`, `Story.live` — which is
`code-is-written-not-generated` under an exemption for framework macros. This procedure changes
what is stored; it does not remove the generated interface, and moving off `enum` entirely is a
larger change than this one.
