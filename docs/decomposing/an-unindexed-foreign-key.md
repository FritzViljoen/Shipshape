# Decomposing an unindexed foreign key — a join the database has to scan

A procedure, meant to be followed by an agent one step at a time. Every step ends with
something to **run**, because a decomposition nobody can verify is a rewrite with extra
confidence.

**What you are aiming at:**

```sql
-- the key the database enforces, and the index that makes it affordable
ALTER TABLE comments ADD CONSTRAINT fk_comments_story
  FOREIGN KEY (story_id) REFERENCES stories(id);
CREATE INDEX CONCURRENTLY index_comments_on_story_id ON comments (story_id);
```

**They are two separate things and both are wanted.** The constraint keeps the data honest; the
index keeps the join and the cascading delete from being a sequential scan. A key without an
index is a correctness win that arrives as a performance regression.

The shape: `comments.order_id` with no index. Every `order.comments` scans the comments table.
It was instant with a thousand rows and it is the incident at ten million.

**This is a runtime failure with a structural cause, which is why it is here.** The survey
files missing indexes under *uncovered* — a file reader cannot know that a table is large. But
it can know that a foreign key has no index, because both facts are written down in
`db/schema.rb`, which is a file this canon already reads. The judgement is which of them
matter; the list is derivable.

**Rails gives you the index when you say `t.references`, and not when you say `t.bigint`.**
That is the whole origin of this shape: the two produce the same column, and only one of them
remembers.

---

## 0. Derive the list from the schema

```sh
ruby -e '
File.read("db/schema.rb").scan(/create_table "(\w+)".*?\n(.*?)\n  end/m).each do |table, body|
  keys = body.scan(/t\.(?:bigint|integer)\s+"(\w+_id)"/).flatten
  leading = body.scan(/t\.index \[([^\]]*)\]/).flatten.map { |list| list[/"(\w+)"/, 1] }
  (keys - leading).each { |key| puts "#{table}.#{key}" }
end'
```

**It compares against the *leading* column of each index, not against membership**, and that is
the part worth understanding. An index on `["order_id", "author_id"]` serves a lookup by
`order_id` and serves a lookup by `author_id` not at all — the database can only use a prefix.
A key sitting in second position is unindexed for its own purposes, and reads as covered to
anyone eyeballing the schema.

**Check:** it runs and returns names you recognise. On a schema that does not use the `_id`
convention it returns nothing, which is a false clean — confirm the convention holds before
believing the silence.

---

## 1. Sort by whether anything actually joins on it

An index is not free. It is paid on every insert, update and delete of that table, and an index
no query uses is pure cost. The list from step 0 is candidates, not work.

```sh
grep -rn "order_id\|belongs_to :order\|has_many :comments" app
```

| What you find | Verdict |
|---|---|
| an association traversed in either direction | index it |
| a `where` on the key | index it |
| written and never queried — an audit trail, an archive | leave it, and write down why |

**Check:** every key on the list is either scheduled for an index or has a recorded reason not
to be.

---

## 2. The index and the foreign key are two things, and you want both

```ruby
add_index :comments, :order_id, algorithm: :concurrently
add_foreign_key :comments, :orders
```

The index makes the read fast. The constraint makes the relationship true — it refuses a
`comments` row pointing at an order that does not exist, and it is what makes
`dependent: :destroy` a statement about behaviour rather than a hope.

**A polymorphic key can have the first and never the second**, which is one of the three
arguments in [a polymorphic association](a-polymorphic-association.md).

**Check:** `db/schema.rb` shows both, and an insert with a bad id is refused by the database
rather than by a validation.

---

## 3. Add them concurrently, one at a time

`add_index` takes a write lock for its duration on Postgres. `algorithm: :concurrently` does
not, and it requires `disable_ddl_transaction!` in the same migration — a pairing people find
out about from an outage.

```ruby
class AddIndexToCommentsOrderId < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_index :comments, :order_id, algorithm: :concurrently
  end
end
```

**One index per migration.** A concurrent build can fail partway and leave an invalid index
behind; noticing that is easy when the migration did one thing.

**Check:** on Postgres, nothing is left invalid:

```sql
SELECT indexrelid::regclass FROM pg_index WHERE NOT indisvalid;
```

---

## 4. The constraint needs the orphans dealt with first

`add_foreign_key` validates the existing rows and fails if any point nowhere. That failure is
the constraint working, and what to do about it is a data decision rather than a migration
problem:

```sql
SELECT COUNT(*) FROM comments c
  WHERE c.order_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM orders o WHERE o.id = c.order_id);
```

**Check:** zero, before the constraint migration runs.

---

## 5. Stop when every traversed key is indexed

```sh
shipshape check
```

The count here is the list from step 0, minus the recorded exceptions.

---

## What this leaves you

**Joins the database can serve, and relationships it can enforce.** A table growing stops
turning a working page into an outage, which is the one thing this shape reliably does.

## What none of this proves

**Nothing here measures a query.** An index existing is not an index being used: a query with a
function on the column, a mismatched type, or a leading-wildcard `LIKE` will not touch it, and
only `EXPLAIN` says so. This gets the index into the schema; whether the planner picks it up is
a different question with a different tool.

**And the list is one-directional.** It finds keys with no index. It does not find the reverse
— indexes nothing queries, a real cost on write-heavy tables — and no static reading can,
because that needs the query log.

**This is a cop that could exist.** `Shipshape/NoNullableColumns` already reads `db/schema.rb`,
so a guard over unindexed keys would run on the same tree with the same instruments. It has not
been written, because whether a given key deserves an index is step 1, and a guard that cannot
do step 1 would fail correct schemas.
