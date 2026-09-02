# Deciding what a stored value is — four things that look identical

A procedure, meant to be followed by an agent one step at a time. Every step ends with
something to **run**, because a decomposition nobody can verify is a rewrite with extra
confidence.

**What you are aiming at:**

```ruby
# before — a column holding an answer the data already contains
orders.status   # 'delivered', set by whatever last remembered to

# after — the facts are rows, and the answer is derived from them
class OrderState < Read
  def call = state_of(@order)   # a delivery row exists, so it is delivered
end
```

Where deriving it every time is genuinely too slow, the column stays as a **cache** and says
so: it is named for the read that rebuilds it, and every write that invalidates it names it
too. What it may not be is the only place the fact lives.

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

**The comment is load-bearing.** Without it the next reader runs the drift read, sees a
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

## 3. Denormalisation — delete the column, and the answer is a read

The one defect. A stored summary of facts still live elsewhere, written because reading them
was inconvenient.

`status` is the canonical instance: `delivered` means a delivery row exists. The column is a
cached answer to a question the data already answers, and like every cache with no invalidation
it goes stale and nobody can say which side is right.

**The fix is not a better column.** It is the existence of rows, read by a read:

```ruby
# A row here is what "priced" means — it used to be `before_adjustments_cents` not being NULL.
class Sales::OrderLinePriceRecord < ApplicationRecord
```

[a state machine](a-state-machine.md) is the full procedure. Before starting it, count the
damage — the drift read is worth running *once you have decided it is this case*:

```sql
SELECT COUNT(*) FROM orders o WHERE o.status IS DISTINCT FROM (
  CASE WHEN EXISTS (SELECT 1 FROM deliveries d WHERE d.order_id = o.id) THEN 'delivered'
       WHEN o.published_at IS NOT NULL THEN 'active'
       ELSE 'draft' END);
```

**Check:** the number. It is not a blocker — it is how many rows are already wrong, which is
the argument for doing the work.

---

## 4. Cache — sanctioned, last resort, and it carries three rules

A saved read answer, kept because the read is genuinely too slow. **Legitimate, and the last
thing to reach for.**

**Name it `{read_name}_cache_record`.** `ListOrderTotals` gets `ListOrderTotalsCacheRecord`.
The name is not decoration: it says which read owns the row, so the pairing is derivable in
both directions and every cache in the system is one grep away. The naming half of "the two
hard problems" is free now, which leaves invalidation as the entire remaining cost — so there
is no excuse left for a cache that does not announce what it is a cache *of*.

**It always has a matching Read, and that read rebuilds it.** Not "the source still exists
somewhere" — one read, named by the record, which returns exactly what the record holds.
Rebuilding is running it. A cache record with no matching read is not a cache; it is a
denormalisation that has been given a reassuring name.

**Invalidation happens in the writes that wrote the rows the read reads.** Not a TTL, not a
callback, not a subscriber — the write that changed the underlying data is the thing that
knows the cache is now wrong, and it says so in the same transaction as the write
([`a-write-is-one-transaction`](../laws/a-write-is-one-transaction.md)). There is no window
in which the rows have moved and the cache has not.

**This is only enumerable because the read is a class.** A read is one read in one file, so
its source tables can be listed; from those, the writes that write them can be listed; and
that set is exactly the set that must invalidate. In a codebase where reads are scope chains
scattered across models, nobody can produce that list, which is why cache invalidation is hard
there and merely tedious here.

```sh
# the read names its tables; these are the writes that must invalidate
grep -rn "OrderLineRecord\|OrderRecord" app/writes app/io_writes
```

**Reach for it last**, after the cheaper answers: an index
([an unindexed foreign key](an-unindexed-foreign-key.md)), a bound
([an unbounded read](an-unbounded-read.md)), or the read doing its work in the database rather
than in Ruby. Slowness is the motivation, not the permission.

**Check:** drop the table in a staging environment and rebuild it by running the read. Nothing
is lost and nothing else broke. If dropping it loses information, it is a snapshot wearing a
cache's name; if you are unwilling to try it, you have a denormalisation with a better name.

**Check:** every write in the list above either invalidates the cache or is one you can say
does not touch what the read reads.

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

**The classification is not checkable by a guard**, and that is why this is a procedure. All
four look the same in `db/schema.rb`: a column holding a value that appears elsewhere. Why the
write happens is not in the schema, and no cop reads a reason.

**The cache's pairing is checkable, and that is a cop that could exist.** `{read_name}_cache_record`
makes the read's name derivable from the record's, so a guard could fail a `*CacheRecord` with
no matching `Read` class — the shape this procedure calls a denormalisation with a reassuring
name. It has not been written. What no guard can add is the other half: that every write
writing the read's source tables invalidates it, which needs to know what the read reads, and
that is the judgement in step 4.

**And a label is not an invalidation.** Writing `_cache_record` on the end of a name records
the decision; it does not rebuild anything, and a cache with a name and no rebuild path is the
same stale column it replaced, now harder to argue with because it looks deliberate.
