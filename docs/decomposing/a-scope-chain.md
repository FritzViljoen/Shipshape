# Decomposing a scope chain — a question whose name was never written

A procedure, meant to be followed by an agent one step at a time. Every step ends with
something to **run**, because a decomposition nobody can verify is a rewrite with extra
confidence.

The shape:

```ruby
Story.where(is_deleted: false).joins(:user).includes(:tags).order(created_at: :desc).limit(25)
```

**What you are aiming at:**

```ruby
class FrontPageStories < Question
  def initialize(reader_id:, page: 1)
    @reader_id = typed(reader_id, Integer)
    @page = typed(page, Integer)
  end

  def call
    rows.map { |row| StorySummary.new(title: row.title, author: row.user.username) }
  end
end
```

The chain gets the name it never had, answers shapes rather than records, and the question it
asks is written once instead of at every call site that assembled it.

**Measured across seven public Rails codebases: 1,600 chains and 952 declared scopes.** It is
the most common shape in this playbook by some distance, and the least often treated as a
decomposition at all.

| Where the chains are | How many |
|---|---|
| a **model** | 456 |
| **elsewhere** — concerns, lib, presenters | 451 |
| a **service** | 293 |
| a **controller** | 283 |
| a **job** | 110 |

---

## 0. The chain is a question, and nobody wrote the question down

A chain is not a query object in disguise; it *is* a query, spelled out at the call site
instead of named. Two consequences follow, and the second is the expensive one:

- **The same question is asked in several places, spelled differently each time.** One site
  adds `includes(:tags)`, another does not; one orders, another does not. Nothing says whether
  those are three questions or one question and two omissions.
- **A change to what the question means has no single home.** "Active excludes suspended now"
  is a grep, and the sites that spell it a fourth way are not in the results.

`Shipshape/CallGraph` already refuses the controller ones — request handling may not reach a
record. **The service and model ones are legal today and unnamed**, which is why they are the
larger half.

**Check:** you have the list.

```sh
grep -rnE "\\.(where|joins|includes|order|limit|group)\\b.*\\.(where|joins|includes|order|limit|group)\\b" app lib
```

---

## 1. Group by the question, never by the SQL

The temptation is to group chains that look alike. Two chains differing only by an `order` are
usually **one question asked by two callers**, one of which did not care about order. Two
chains that look identical but are called from "the moderator queue" and "the public feed" are
usually **two questions** that happen to agree today, and they will diverge the first time a
moderator needs to see something a reader may not.

`model-concerns-not-groups`. Ask what each caller is *for*, not what it selects.

**Check:** none — this is the judgement the procedure exists to leave room for.

---

## 2. Name the answer, not the question

`StoriesWhereNotDeletedJoinUser` is the SQL with the punctuation removed. `FrontPageStories`
is the question. The name is what the next person greps for, and they will grep for the thing
they want, not for the clauses that produce it.

```ruby
class FrontPageStories < Question
  def initialize(reader_id:, page: 1)
    @reader_id = typed(reader_id, Integer)
    @page = typed(page, Integer)
  end

  def call
    rows.map { |row| StorySummary.new(title: row.title, author: row.user.username, ...) }
  end
end
```

**Check:** the class name contains no clause word — no `where`, `by`, `with`, `joined`.

---

## 3. The scope moves with it

A `scope :active, -> { where(deleted_at: nil, suspended: false) }` on the record is the rule
about what *active* means, living on the thing that maps rows —
[`persistence-holds-no-behaviour`](../laws/persistence-holds-no-behaviour.md). It travels into
the question that needed it.

**A scope used by exactly one question is not shared, and never was.** A scope used by six is the
interesting case: either it is one rule with six callers, in which case it becomes one question
the six use, or the six mean subtly different things and the scope has been hiding that.

**Check:** `Shipshape/PersistenceHoldsNoBehaviour` is quieter, and no scope is left that only
one question uses.

---

## 4. `includes` is a claim about what the caller renders

A chain carrying `includes(:tags)` is encoding what some template touches, in the question, at a
distance from the template. Move it and it is not lost — it is **fixed**: the shape the question
answers declares exactly which fields exist, so the N+1 becomes impossible rather than avoided.

This is the strongest argument for doing this work at all, and the one nobody makes. A shape
cannot lazily load anything, because it holds no record —
[`a-shape-is-composed-not-flattened`](../laws/a-shape-is-composed-not-flattened.md) and the
generated `Shape` refuse it at construction.

**Check:** the question's own test asserts the number of database calls, and the number does not
depend on how many rows come back.

---

## 5. The cost, stated before you start

`Question#call` refuses anything that is not a shape, so the template stops receiving records —
which is the whole of [a form that fails](a-form-that-fails.md), and it is a bigger job than
naming the question was. **Do it per template, not per question**: a question answering shapes whose
template still calls record methods fails at render, in a browser, whenever somebody looks.

**Check:** the template names only methods the shape defines.

---

## 6. Sweep the call sites

Every site that spelled the chain by hand now calls the question. That is
[a call-site sweep](a-call-site-sweep.md), and the sites that spelled it a fourth way are the
ones the grep in step 0 missed — so the count only settles once `Shipshape/CallGraph` is
silent on the tree.

**Check:** `shipshape check` — the count falls and never rises.

---

## What this leaves you

**A question asked once, with a name.** The chain that was assembled differently at nine call
sites is one class, and changing what the front page means is one edit rather than nine. What
it answers is shapes, so nothing downstream can lazily load or write through what it was given.

## What none of this proves

**Nothing here shows the two chains you merged were the same question.** Every check passes on
a merge that was wrong: the SQL is identical, the tests pass, and the defect surfaces the first
time one caller needs a condition the other must not have. That is `model-concerns-not-groups`
and no tool makes it.

The other one to expect: **a question that now returns fewer rows because a scope was applied
that the old chain forgot** — or more, because one it had was dropped. The chains differed and
the difference was the point. A characterisation test that records the ids each call site
returned, before the change, is the only thing that catches it.
