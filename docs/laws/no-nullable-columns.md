# `no-nullable-columns` — Every column is NOT NULL

No column may be nullable. If a value genuinely does not exist for some rows, that is a
missing table, not a missing value.

A null is not "off", not "inherit", not "not applicable", not "we lost it" — it is all of
them at once, and no reader can tell which. Every meaning given to it is a fact nobody
declared.

**A nullable foreign key is the common case, and it is usually two things sharing one
table.** The way to say "nobody has said" is the absence of a row: a join, with a uniqueness
constraint on the key. The unique index is half the fix — without it the join holds two
answers to one question.

**A column may be nullable only between two statements of one migration method.** A NOT NULL
column cannot be added to a populated table in one statement, so it is added nullable,
filled, and promoted — and the promotion comes later in the same method. A nullable column
that outlives its migration is what this law forbids.

- **Principle:** `absence-is-absence`
- **Guard:** `Shipshape/NoNullableColumns`, over migrations. Covers creation and alteration,
  resolves a reference to the column it really creates, exempts the reverse direction, and
  holds the same-method promotion rule.

- **Guard's limit:** it reads **migrations, not the live schema**. A column made nullable by
  anything else — a hand-run statement, a tool, a vendored migration — is invisible, and a
  passing run therefore proves what this repo's migrations did, not what the database holds.
  Migrations vendored from an engine are excluded, because holding someone else's file to a
  house rule only ever means a red build.
