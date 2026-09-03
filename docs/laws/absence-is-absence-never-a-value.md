# `absence-is-absence-never-a-value` — A gap is a missing row, not a value in one

No column may be nullable. **The failure is a concern nobody modelled; the null is only what
that looks like in a column.** If a value genuinely does not exist for some rows, that is a
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
- **Guard:** `Shipshape/AbsenceIsAbsenceNeverAValue`, over migrations, and only for a table
  some Record in this repository claims. Covers creation and alteration, resolves a
  reference to the column it really creates, exempts the reverse direction, and holds the
  same-method promotion rule.

- **Guard's limit:** it reads **migrations, not the live schema**. A column made nullable by
  anything else — a hand-run statement, a tool, a vendored migration — is invisible, and a
  passing run therefore proves what this repo's migrations did, not what the database holds.
  Migrations vendored from an engine are excluded, because holding someone else's file to a
  house rule only ever means a red build. `shipshape tables` reads `db/schema.rb` itself and
  names every nullable column no migration in the repository declares — the set this guard
  cannot see, clean run or not.

  **It also fires only on a table it can see is owned.** A table counts as claimed when a
  file under the `record` kind's own paths either assigns `self.table_name` to it — a
  literal string or a bare symbol, both read the same way — or declares a class whose
  superclass is a listed record base class, in which case the guard guesses the table name
  the way Rails would: pluralised, underscored, demodulised, and — for a class written the
  compact way, `Module::Class` — prefixed with the nearest enclosing module's own
  `table_name_prefix`, read from whichever file under `app/` or `lib/` declares that module
  alone and returns the prefix as a literal string.

  Measured against a real 233-table, 299-model schema this claims 201 of them. Of the 32 it
  still cannot see, 31 are a table an engine or a gem owns outright with no Record file in
  this repository claiming it at all (the intended trade, not a defect), a pure join table
  with no Record of its own, or a class built on a gem's own base rather than a listed one
  (a session or a cached-settings class, say) — all cases this guard was never meant to
  reach. The other one is a namespaced class written the *other* way,
  `module Foo; class Bar < ApplicationRecord; end; end` — this guard reads the `class` line
  without ever seeing the enclosing `module` line above it, so a `table_name_prefix` has
  nothing to attach to even when `Foo` declares one, and the real table it owns stays silent.

  It cannot see a table that no Record file mentions at all — hundreds of them in an
  adopting repository — and it never claims to have modelled what such a table means; it
  reports only what a column it inspected says. It also cannot see: a genuine irregular
  plural (`Person` guessed as `persons`, not `people`) — the regular rule now matches Rails'
  own (consonant-`y` to `ies`, vowel-`y` to plain `s`, an already-plural class name left
  alone), but a true irregular has no signal in its own spelling for any rule to read; a
  table name, or a `table_name_prefix`, built from anything but a literal string; a module
  whose prefix-declaring file also declares a second top-level module, which leaves no
  static way to say which one the prefix belongs to; a subclass of another record rather
  than of the listed base classes, which claims nothing of its own even when Rails would
  derive one from it; the nested-`module` namespace form described above; or a record living
  outside the configured `record` kind's paths.
