# Deciding what a stored value is — four things that look identical

A procedure, meant to be followed by an agent one step at a time. Every step ends with
something to **run**, because a decomposition nobody can verify is a rewrite with extra
confidence.

The shape: a column holding something the database could work out for itself. A `status`. A
`price_paid`. A `comments_count`. A `total`.

**Unusually for this playbook, three of the four answers are "leave it alone".** This procedure
exists because the wrong one gets deleted: a stored value that disagrees with its source looks
like a bug in every case, and in two of the four it is the value doing its job.

---

## The observation that cannot classify anything

Take the obvious test — recompute the value from its source and see whether it still agrees.

- A **denormalised** `status` that disagrees with the delivery rows has **drifted**. Bug.
- A **snapshot** `price_paid` that disagrees with the current rate card is **correct**. That is
  what it is for: the price as sold must not move when the rate card does.

**Identical evidence, opposite verdicts.** So agreement cannot tell you what you are looking
at, and a check built on it will tell you to delete the one column you must keep.

---

## 0. Classify by the write path, not by the data

The question is not *does it match* but **why was it written**. That is answerable, and it is
answerable from the code rather than from a console.

```sh
git log -S "price_paid" --format='%as %s' -- app | tail -20
grep -rn "price_paid\s*=\|price_paid:" app
```

| Why it was written | What it is |
|---|---|
| the source will move, and the old value is the fact | **snapshot** |
| two parties agreed it, and it now binds | **commitment** |
| reading the source was slow, and this is a saved answer | **cache** |
| reading the source was inconvenient | **denormalisation** |

**The last row is the only defect**, and it is the only one whose justification is about the
programmer rather than about the domain.

**Check:** every stored derivation you are looking at has one of the four labels, and you can
point at the code that writes it.

---

## 1. Snapshot — keep it, and say so where it is written

A value copied at a moment because the value at that moment *is* the fact. The price as sold.
The address it shipped to. The rate that applied.

**It cannot be re-derived**, because the source has moved on and the source's job is to move
on. Deleting it does not normalise anything; it loses the only record.

```ruby
# What is held here is the price as sold — it must not move when the rate card does.
@before_adjustments = typed(before_adjustments, Money, allow_nil: true)
```

**The comment is load-bearing.** Without it the next reader runs the drift query, sees a
disagreement, and files a bug — or fixes it.

**Check:** the write site says, in a sentence, why the copy is taken.

---

## 2. Commitment — keep it, and never edit it

Stronger than a snapshot: an amount two parties agreed, which now binds. An invoice line.

**A commitment is append-only.** A correction is a new line, not an update — because the thing
that was agreed remains true even after it turns out to be wrong, and an invoice that changes
retroactively is not an invoice.

The Order copying the catalogue price and the statement recording the agreed price are **two
facts**, taken at two moments, by two acts. Neither derives from the other, and collapsing
them is how a discount becomes unexplainable.

**Check:** nothing issues an `UPDATE` against the table. The only writes are inserts.

---

## 3. Denormalisation — delete the column, and the answer is a query

The one defect. A stored summary of facts still live elsewhere, written because reading them
was inconvenient.

`status` is the canonical instance: `delivered` means a delivery row exists. The column is a
cached answer to a question the data already answers, and like every cache with no invalidation
it goes stale and nobody can say which side is right.

**The fix is not a better column.** It is the existence of rows, read by a query:

```ruby
# A row here is what "priced" means — it used to be `before_adjustments_cents` not being NULL.
class Sales::OrderLinePriceRecord < ApplicationRecord
```

[a state machine](a-state-machine.md) is the full procedure. Before starting it, count the
damage — the drift query is worth running *once you have decided it is this case*:

```sql
SELECT COUNT(*) FROM orders o WHERE o.status IS DISTINCT FROM (
  CASE WHEN EXISTS (SELECT 1 FROM deliveries d WHERE d.order_id = o.id) THEN 'delivered'
       WHEN o.published_at IS NOT NULL THEN 'active'
       ELSE 'draft' END);
```

**Check:** the number. It is not a blocker — it is how many rows are already wrong, which is
the argument for doing the work.

---

## 4. Cache — sanctioned, last resort, and it must say what invalidates it

A saved query answer, kept because the query is genuinely too slow. **Legitimate, and the last
thing to reach for.**

**Name it `*_cache_record`.** The naming half of "the two hard problems" is free now; there is
no excuse left for a cache that does not announce itself, and one word in the name makes every
cache in the system greppable. What is not free is invalidation, which is the entire remaining
cost — so the gate is:

> **You may add a cache record when you can name what invalidates it.** Slowness is the
> motivation, not the permission.

Four obligations, all of them consequences of it being a cache and not a fact:

- **the query still exists**, and it is the source of truth
- **nothing writes to the record** except the thing that rebuilds it from that query
- **dropping it loses nothing** — if dropping it loses information, it is a snapshot wearing a
  cache's name, and it is now a snapshot with no protection
- **the event that makes it stale is written down**, next to the record

**Reach for it last**, after the cheaper answers: an index
([an unindexed foreign key](an-unindexed-foreign-key.md)), a bound
([an unbounded read](an-unbounded-read.md)), or the query doing its work in the database
rather than in Ruby.

**Check:** drop the table in a staging environment and rebuild it from the query. Nothing is
lost and nothing else broke — and if that is not a thing you are willing to try, you have a
denormalisation with a better name.

---

## 5. Stop when every stored derivation has a label

```sh
shipshape check
```

---

## What this leaves you

**A reader who can tell, from the code, which of four things a column is** — and therefore
whether a disagreement with the source is a bug, a correctness property, or a stale cache due
a rebuild.

## What none of this proves

**Nothing here is checkable by a guard**, and that is why it is a procedure. All four look the
same in `db/schema.rb`: a column holding a value that appears elsewhere. The classification
lives in why the write happens, which no cop reads.

**And a label is not an invalidation.** Writing `_cache_record` on the end of a name records
the decision; it does not rebuild anything, and a cache with a name and no rebuild path is the
same stale column it replaced, now harder to argue with because it looks deliberate.
