# Decomposing an unbounded read — a read with no answer to "how many?"

A procedure, meant to be followed by an agent one step at a time. Every step ends with
something to **run**, because a decomposition nobody can verify is a rewrite with extra
confidence.

**What you are aiming at:**

```ruby
class ListStories < Read
  MAX = 100

  def initialize(page:, per_page:)
    @page = typed(page, Integer)
    # a caller asking for 10,000 gets 100 — the ceiling is the read's, not the caller's
    @per_page = [typed(per_page, Integer), MAX].min
  end
end
```

Every read has a ceiling it owns. A page size that arrives from outside is a request, not an
instruction, and the read is the only thing that knows what it can afford to answer.

The shape: `Story.all.each`, an index action with no pagination, a read that answers "every
row matching this". It worked for two years and then one account had forty thousand rows.

**This is the one failure in this playbook that is correct until it is not.** Nothing is
mis-shaped: the read reads, the operation answers a `Result`, the call graph is satisfied. It
is a *size* defect, and size is a runtime fact — which is exactly why no cop here holds it, and
why the answer has to be structural instead: make the bound an argument, so that a caller
cannot ask for "all" without saying so.

---

## 0. Find the reads with no ceiling

```sh
grep -rn "\.all\b\|\.each\b\|\.map\b" app/reads app/io_reads | grep -v "find_each\|limit\|first("
```

Then the edges, because an index action is the commonest instance and does not look like one:

```sh
shipshape edges
```

**A read is a candidate if you cannot answer "what is the largest this can return?"** Not
"what is it today" — what is the largest, given the data model. A read over a table that grows
per user per day has no ceiling; one over a table of currencies does.

**Check:** every read on the list has a stated maximum, or is on the work list.

---

## 1. Three shapes, and they take different bounds

| What the caller wants | The bound |
|---|---|
| a page of results for a person to look at | `page:` and `per_page:`, typed, with a maximum |
| every row, for a job that processes them | a cursor — `after_id:` — and the job loops |
| a count, or a sum | do it in the database; never load rows to count them |

**The third is the cheap win and it is common.** `Story.where(...).map(&:amount).sum` loads
every row to add a column up. `sum(:amount)` is one read returning one number, and the fix is
smaller than the sentence describing it.

**Check:** each read has a shape, and none of them is "load everything and reduce in Ruby".

---

## 2. The bound is an argument, and it is typed

```ruby
class ListStories < Read
  MAX = 100

  def initialize(page:, per_page:)
    @page = typed(page, Integer)
    # a caller asking for 10,000 gets 100 — the ceiling is the read's, not the caller's
    @per_page = [typed(per_page, Integer), MAX].min
  end
end
```

**A caller-supplied limit with no ceiling is the same defect with an extra step**, and it is
worse, because now the unbounded read is reachable from a query parameter. `per_page=1000000`
is a denial of service written by whoever left the maximum out.

`Shipshape/TypedArguments` makes the argument declare itself; the ceiling is yours.

**Check:** every paginating read has a constant maximum, and a test that asks for more than it
and gets the maximum.

---

## 3. A job reads with a cursor, not a page

Pagination by offset re-reads the rows it skipped, and drifts when rows are inserted underneath
it — a job paging through a growing table processes some rows twice and misses others.

```ruby
# the bound the job takes, and the value it answers, are the same shape
def call
  rows = StoryRecord.where("id > ?", @after_id).order(:id).limit(BATCH)
  success(Batch.new(stories: rows.map { |row| Story.from(row) }, last_id: rows.last&.id))
end
```

**And the loop belongs to a workflow, not to the read.** A read is one read
([`a-read-writes-nothing`](../laws/a-read-writes-nothing.md)); the thing that calls it until it is
empty is a sequence, which is what a workflow is for.

**Check:** the job's read returns a bounded batch and the cursor it ended on.

---

## 4. The view gets a page, not a collection

An index that renders "all stories" hands the template an unbounded array, and adding
pagination later means changing the template, the action and the read at once.

**A page is a shape**: the rows, the page number, whether there is another one. A view component
holds shapes and nothing else, so this falls out of the rules already in force —
[a fat controller](a-fat-controller.md), step 5.

**Check:** the template receives one shape and does not call `count` on it.

---

## 5. Stop when every read states its ceiling

```sh
shipshape check
```

The count here is again not a cop's: it is your list from step 0, and it is done when every
entry has a bound or a written reason it does not need one.

---

## What this leaves you

**A read whose worst case you can state.** The largest response is a constant in the code
rather than a property of the busiest account, and a table growing does not turn a working page
into an outage.

## What none of this proves

**Nothing here measures anything.** A read bounded to 100 rows that each trigger three
association loads is 300 reads, bounded, and this procedure calls it done. That is
[N+1](https://github.com/flyerhzm/bullet), it is a runtime fact, and Bullet finds it — the
survey says so and this procedure does not change it.

**And a bound is not an index.** `ORDER BY created_at LIMIT 100` on an unindexed column sorts
the whole table to return a hundred rows. The bound made the response small; the database still
did all the work, and only an `EXPLAIN` says so.
