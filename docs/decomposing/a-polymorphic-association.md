# Decomposing a polymorphic association — a class name in a data column

A procedure, meant to be followed by an agent one step at a time. Every step ends with
something to **run**, because a decomposition nobody can verify is a rewrite with extra
confidence.

**What you are aiming at:**

```sql
-- before: one table, a type string, and no foreign key the database can enforce
comments (id, commentable_type, commentable_id, body)

-- after: one table per owner, and a key the database checks
article_comments (id, article_id REFERENCES articles, body_id REFERENCES comment_bodies)
story_comments   (id, story_id   REFERENCES stories,  body_id REFERENCES comment_bodies)
```

A polymorphic key is a foreign key the database cannot check, because the table it points at is
in a string. Splitting it buys referential integrity back — and usually reveals that the two
owners wanted different columns anyway.

The shape: `belongs_to :commentable, polymorphic: true`, and a table with `commentable_type`
and `commentable_id`. Two columns, one association, any number of parents.

**Three things are wrong with it, and they are independent:**

- **No foreign key is possible.** The database cannot enforce that `commentable_id` names a row
  anywhere, so referential integrity is application-only — which means it is not integrity, it
  is a convention that holds until a delete happens outside the application.
- **`commentable_type` stores a class name.** The database now holds Ruby identifiers, and a
  rename is a data migration. `code-is-written-not-generated` argues against a reader having to
  resolve a name at runtime; this stores the runtime name in a row.
- **One table holds several relationships.** A comment on an article and a comment on a photo
  are joined the same way and may not be the same thing at all — the god-record reading
  ([a god record](a-god-record.md)) applied to a join.

---

## 0. Ask the data how many types there actually are

```sql
SELECT commentable_type, COUNT(*) FROM comments GROUP BY 1 ORDER BY 2 DESC;
```

**Run this before anything else, because the answer decides the procedure.** The shape is
justified by "any number of parents"; the data almost never has any number. Two or three is
usual, one dominant and a long tail is common, and a type with a handful of rows is often a
feature that was abandoned.

**Check:** you have the counts, and you can name what each type is for. A type you cannot
explain is the first thing to look at.

---

## 1. A type present in the data and absent from the code is the finding

Compare the list against the classes that declare the other half:

```sh
grep -rn "has_many :comments\|has_one :comment" app
```

**A `commentable_type` with no matching `has_many` is orphaned data** — rows pointing at a
class that no longer claims them, or no longer exists. Nothing raises: the association returns
`nil` when the constant is missing, or blows up at the one call site that dereferences it.

**Check:** every type in the data has a class that declares the inverse, or is on a list of
rows to delete.

---

## 2. One table per relationship, and the join becomes enforceable

```ruby
# before — unenforceable, and two kinds of comment share a table
create_table :comments do |t|
  t.string :commentable_type, null: false
  t.bigint :commentable_id, null: false
end

# after — the database holds the relationship, and can say no
create_table :article_comments do |t|
  t.references :article, null: false, foreign_key: true
  t.references :body, null: false, foreign_key: true
end
```

**The body of the comment stays one table if it really is one thing.** What splits is the
*join*, not necessarily the content — a `comments` table plus one join table per parent keeps
the text in one place and makes each relationship a real foreign key.

**Do not skip the "is it one thing" question.** If an article comment carries a moderation
state and a photo comment does not, they were never one thing and the shared table was the
polymorphic association hiding it.

**Check:** every new join column is `NOT NULL` with a foreign key —
[`no-nullable-columns`](../laws/no-nullable-columns.md) applies here and is the point.

---

## 3. If it must stay polymorphic, make the type a real domain

Sometimes the parent genuinely is open-ended — an audit trail over every table, an attachment.
Then the column still must not hold a class name.

- store a **domain value** you control: `"article"`, not `"Article"`
- keep the mapping from value to class in one place, written out, not derived by
  `constantize`
- a rename in the code is then a rename in one file, not a data migration

**Check:** `grep -rn "constantize\|safe_constantize" app` returns nothing that reads this
column. `Shipshape/NoGeneratedInterfaces` catches the `send` family, not `constantize` —
this one is on you.

---

## 4. Migrate one type at a time

Take the smallest type first, not the largest: it is the cheapest to verify and the least
likely to be load-bearing. Dual-write, backfill, verify, move readers, stop writing the old
pair — the order in [a serialized column](a-serialized-column.md), step 3, which is the same
migration shape.

```sql
-- the verification, before any reader moves
SELECT COUNT(*) FROM comments c
  WHERE c.commentable_type = 'Article'
    AND NOT EXISTS (SELECT 1 FROM article_comments a WHERE a.body_id = c.id);
```

**Check:** zero, on production-shaped data.

---

## 5. Stop when every join is a foreign key

```sh
shipshape check
```

---

## What this leaves you

**The database enforces what the code was promising.** A deleted article cannot leave comments
behind, a bad id cannot be written, and a class rename is a code change.

## What none of this proves

**Query fan-out is worse, and that is the real cost.** "All comments by this user, across
everything" was one query and is now a union over N tables, and it grows with each parent
type. If that query is on a hot path, measure it before committing to the split — this
procedure buys integrity with joins, and the trade is not free.

**And nothing here finds the orphans that already exist.** The rows pointing at deleted
parents are in the table now; the new foreign key will refuse to be created until they are
dealt with, which is the migration failing rather than the procedure working. Count them
first:

```sql
SELECT COUNT(*) FROM comments c WHERE c.commentable_type = 'Article'
  AND NOT EXISTS (SELECT 1 FROM articles a WHERE a.id = c.commentable_id);
```

A non-zero answer is a decision — delete them, or keep them and admit the relationship was
never required — and it is a decision for whoever owns the data, not for this procedure.
