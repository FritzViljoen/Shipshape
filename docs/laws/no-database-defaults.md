# `no-database-defaults` — No column carries a database default

Creation and update timestamps excepted.

A default in the schema is a **second place deciding a value**, and it drifts from the
first. The column refuses the gap; the domain names the fallback. Two declarations of one
fact leave a reader unable to say what the system holds — not because nothing states it,
but because two things do and they disagree.

This is the mirror of [`no-nullable-columns`](no-nullable-columns.md). One forbids a gap
being given a meaning; this forbids a fact being stated twice. Both defects end in the same
place: a value nobody can point at the source of.

- **Principle:** `absence-is-absence` governs. `one-thing-one-place` also produces it — a
  fact has one home — and on conflict `absence-is-absence` wins, because the reason a
  default is tempting at all is a column that should have refused the gap.
- **Guard:** `Shipshape/NoColumnDefaults`, over migrations.
- **Guard's limit:** migrations only, with the same consequence as
  [`no-nullable-columns`](no-nullable-columns.md) — a default applied outside them, by a
  database-side trigger or by hand, is invisible. It also cannot see a default expressed as
  a column's generated-value clause rather than as a default.

**A note on the framework fighting this.** A general-purpose cop that wants a default
alongside NOT NULL so a migration survives a populated table conflicts with both laws
directly. Turn that cop off; the promotion rule in
[`no-nullable-columns`](no-nullable-columns.md) is the answer it was reaching for.
