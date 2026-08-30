# `personal-data-is-declared-and-erasable` — Where a person's data is, is written down; what happens to it on erasure is decided once

Every column holding something about a person is named in `app/shipshape/personal_data.rb`,
with one of four routes: `:delete_row`, `:anonymise`, `:retain_with_reason`, `:not_personal`.
Every association that owns children says what happens to them with `dependent:`.

## This is not a compliance check, and saying so is part of the law

**A green build here is not evidence of anything legal, and a guard somebody mistakes for
legal assurance is worse than no guard at all.** That is not a disclaimer bolted on the end;
it is the reason the scope is drawn where it is.

What these guards do: make the **inventory** exist, keep it from going stale, and force the
erasure decision to be made once — while the person who added the column still remembers what
it holds — rather than during an incident by whoever is on duty.

What they do not do, and cannot:

- whether you had a lawful basis to collect it
- whether the retention period is justified
- whether an anonymisation is irreversible **in fact** — a hash with the key retained is a
  pseudonym, and this cannot tell the difference
- whether consent was obtained, recorded, or withdrawn
- anything at all about data **outside this repository's database**

## Erasure is unimplementable without an inventory

Not difficult — unimplementable. You cannot delete what nobody can enumerate, and nobody
enumerates two hundred tables from memory. Without a written inventory every request becomes
fresh archaeology, performed under time pressure, answered differently each time, by whoever
happens to be available.

The inventory is cheap to keep and expensive to reconstruct, and the moment it is cheapest is
the moment the column is added. So that is where the guard puts the cost.

**`:not_personal` is a real answer and a required one.** `class_name`, `filename`,
`host_address` match the pattern and are not about a person. Saying so once costs a line and
stops the question being asked again — and it is the difference between an inventory and a
list of things somebody once suppressed.

**`:retain_with_reason` is the answer that must never be silent.** A statutory retention
period on a financial record is legitimate and common. The reason goes next to it, in a
comment, because that comment is the only record of why the data survived a request to delete
it — and it is what somebody will be asked for.

## A nullable foreign key is an erasure bug

This law and [`no-nullable-columns`](no-nullable-columns.md) meet here. A nullable
`user_id` says "sometimes nobody", which means erasure has to *find and clear* it, in code
somebody remembers to write. The join-table shape that law prescribes turns the same fact into
a row you delete — and a row that is gone cannot be forgotten about, whereas a column somebody
did not null out looks exactly like a column that was always empty.

**Most of the personal data is not here.** Logs, backups, analytics, the warehouse, a third
party's store. This is repository-scoped and sees the database; it does not know what fraction
of the whole that is, and neither does anybody who has not gone and looked.

- **Principle:** `nothing-is-hidden`
- **Guard:** `Shipshape/PersonalDataIsDeclared`, over `db/schema.rb`. For every column whose
  name suggests a person, asks the registry what happens to it, and fails when nothing does.
- **Guard:** `Shipshape/AssociationsSurviveErasure`, over the record tree. Fails a `has_many`,
  `has_one` or `has_and_belongs_to_many` with no `dependent:`, because the default leaves the
  children behind and nobody chose that.
- **Guard:** the generated `personal_data.rb` and the installed
  `personal_data_is_erasable_test.rb` — architecture. The registry is the declaration; the
  test asks the **connection** rather than the schema file, so a column added by a hand-run
  statement or by another service sharing the database is caught, and a declared table or
  column that no longer exists is caught too, because a stale inventory reads as coverage.
- **Guard's limit:** the cop matches **column names** from a list, so a field named for the
  business rather than for the person — `contact_ref`, `handle`, `party_key` — is invisible
  until somebody adds it. The list is the fact, and a name not on it is unexamined rather
  than cleared.

  It reads `db/schema.rb`, which is what this repository's migrations produced, not what the
  database holds — and **a repository using `structure.sql` gets nothing from the cop at all,
  silently**, which is indistinguishable from a clean schema. Discourse is one. For those the
  installed test is not an extra check but the only one, because it asks the connection and
  does not care how the schema is stored.

  A **boolean is never reported**, whatever it is called: `is_from_email` and `show_email` are
  flags, and asking somebody to classify them is a guard firing on correct code.

  It cannot tell whether a route is **reachable**: a column marked
  `:anonymise` with nothing that anonymises it passes, because a declaration is not a
  capability. It cannot check `dependent: :nullify` against a NOT NULL column, which fails at
  runtime, on the delete, which is the worst moment to discover it.

  And it sees one database in one repository. **The fraction of the personal data that
  represents is unknown to it**, so the number it reports is a floor and never a total.
