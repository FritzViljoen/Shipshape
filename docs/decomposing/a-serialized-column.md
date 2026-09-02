# Decomposing a serialized column — a schema nobody declared

A procedure, meant to be followed by an agent one step at a time. Every step ends with
something to **run**, because a decomposition nobody can verify is a rewrite with extra
confidence.

**What you are aiming at:**

```sql
-- before: a blob whose keys nobody declared, and which no constraint can reach
settings jsonb

-- after: the keys that turned out to be real become columns the schema knows about
ALTER TABLE accounts ADD COLUMN timezone text NOT NULL;
```

A column can be NOT NULL, indexed, and checked; a key inside a blob can be none of those. What
stays in the blob is what is genuinely per-row and unqueried — and saying which is the work.

The shape: `serialize :settings, JSON`, or a `jsonb` column, holding eleven keys that eleven
places read. It was one column when it was written, which was the appeal.

**A blob is a schema with no declaration and no constraints.** Not a missing schema — an
undeclared one. The keys exist, they have types, some are required; none of it is written
anywhere, so every reader guesses and the guesses drift. `Shipshape/NoNullableColumns` refuses
a gap in a column and cannot see inside one, so a blob is where absence goes to stop being
checkable: a key that is missing, present-and-null, and present-as-`""` are three states the
column cannot tell apart and every reader handles differently.

---

## 0. Separate the two things called a blob, because one of them is fine

| What it holds | Verdict |
|---|---|
| Facts the application **reads by key** — `settings["timezone"]`, `payload["amount"]` | an undeclared schema. This procedure. |
| A payload it **never looks inside** — an inbound webhook body kept as evidence, a raw API response for support | legitimately opaque. Leave it. |

**The test is whether anything indexes into it.** A blob written once and read only by a human
debugging an incident is a stored artefact, and giving it columns would be inventing a schema
for something whose shape you do not control.

**Check:** you can say which of the two this column is, with a grep that supports the answer.

---

## 1. Inventory the keys actually read

```sh
grep -rn "settings\[" app lib | grep -o 'settings\["\?[a-z_]*' | sort | uniq -c | sort -rn
```

Then the same for writes, and for `dig`, `fetch`, and symbol keys. **The two lists differ**,
and both differences matter: a key written and never read is dead, and a key read and never
written is a `nil` that some branch is already handling.

**Then ask the database, because the code is not the whole story:**

```sql
SELECT DISTINCT jsonb_object_keys(settings) FROM accounts;  -- Postgres
```

A key in the data and not in the code is a fact from an older version of the application that
something may still depend on. A key in the code and not in the data is a default nobody has
exercised.

**Check:** you have three lists — read, written, present in data — and can explain each
difference.

---

## 2. Sort the keys, and most of them are columns

| What the key is | What it becomes |
|---|---|
| a fact about this row, always present | a column, `NOT NULL` |
| a fact about this row, sometimes present | **a row in a joined table** — absence is a missing row, not a missing key ([a nullable column](a-nullable-column.md)) |
| a fact about something else | a column on that table |
| a set of related keys that move together | a table of their own, or a shape held by one |
| unread | delete it |

**The sometimes-present case is the one this shape exists to hide**, and it is where the blob
felt like a win: "some accounts have a `billing_contact`, so it does not deserve a column."
That reasoning produces a nullable column when it is honest and a blob when it is not. The
answer is the same either way — a join, with a uniqueness constraint on the key.

**Check:** every key from step 1 has a destination or is marked dead.

---

## 3. Migrate one key at a time, and read from the new place last

The order that stays green:

1. add the column or table, `NOT NULL` with the value backfilled
2. write both — the blob and the new place — in the same write, in one transaction
   ([`a-write-is-one-transaction`](../laws/a-write-is-one-transaction.md))
3. backfill the rows written before step 2
4. verify: nothing disagrees
5. move the readers
6. stop writing the blob key, and drop it from the data

```sql
-- step 4, and it is not optional: the count must be zero
SELECT COUNT(*) FROM accounts WHERE settings->>'timezone' IS DISTINCT FROM timezone;
```

**Step 4 is the whole procedure.** Steps 1 to 3 are mechanical; the reason this shape is
dangerous to unpick is that the blob's history is not uniform, and only a read over real rows
says so.

**Check:** the verification read returns zero, on production-shaped data, before any reader
moves.

---

## 4. One key at a time, and never a big-bang migration

The temptation is a single change that adds eleven columns and deletes the blob. It cannot be
verified — a failure in step 4 for one key means reverting all eleven — and it cannot be
deployed in stages, so old code and new schema overlap with no dual-write.

**Check:** the blob has one fewer key than it did, and the suite is green.

---

## 5. Stop when what remains is opaque or gone

```sh
shipshape check
```

---

## What this leaves you

**Columns that declare themselves.** `NOT NULL` means required, a missing row means absent, and
a reader learns the shape from `db/schema.rb` instead of from eleven call sites and a
production console.

## What none of this proves

**Old rows have different key sets, and nothing in this procedure finds that except step 4.**
A blob written across three years of deploys holds three years of shapes: keys renamed in code
and not in data, values that were strings and became integers, a boolean stored as `"true"`
in the rows from one particular importer. The verification read finds the disagreements it
was written to look for and no others.

**And YAML is worse than JSON here.** `serialize :settings` with the default coder stores
marshalled Ruby, so a class rename makes old rows unreadable, and reading them at all
instantiates whatever the YAML names. Treat a YAML column as a migration that has to happen
rather than one that should.
