# Decomposing a query that writes — the write nobody can find

A procedure, meant to be followed by an agent one step at a time. Every step ends with
something to **run**, because a decomposition nobody can verify is a rewrite with extra
confidence.

The shape:

```ruby
class FindOrCreateAllQuery
  def call
    ConsumerApp.create!(app_bundle: bundle, platform: :ios)
  end
end
```

That is a real file from a real repository, named `...Query`, calling `create!`. 376 of these
across seven repositories, and the call sites all read like reads.

**What you are aiming at:**

```ruby
class RegisterConsumerApp < Workflow
  def call
    found = FindConsumerApp.call(actor: actor, name: @name)   # the read
    return found if found.value

    CreateConsumerApp.call(actor: actor, name: @name)         # the write
  end
end
```

The read and the write become two operations with two names, and the sequence that used to hide
inside one method becomes a workflow that states it.

---

## 0. Understand why nothing else catches this

The call matrix **allows** a query to reach a record — that is what a query is for — so
`CallGraph` is silent by design. It governs which kinds talk, never what they say.

And the cost is not tidiness. **A query opens no transaction, because a read needs none.** The
generated `Query` deliberately has none. So the write runs outside any transaction the canon
knows about: a caller sequencing two queries has no rollback for the second, and every name on
the path says nothing happened.

```sh
shipshape next --json
```

`QueriesOnlyRead` names each site.

**Check:** you can state, for the file in hand, what happens if the process dies immediately
after the write.

---

## 1. Sort them — three shapes, three answers

| What it is | What it becomes |
|---|---|
| `find_or_create_by`, `first_or_create` | a **command**; the caller decides when to create |
| a read that also touches, counts, caches, or stamps | a query, with the write moved to its caller |
| a write with a read stapled to the front | a command that answers what it wrote |

**`find_or_create_by` is the commonest and the most interesting.** It is two operations wearing
one name, and the reason it exists is almost always that the caller did not want to think about
which case it was in. That is exactly the decision that belongs at the call site: the caller
knows whether it is registering something new or looking one up, and the two have different
permissions, different audit meaning, and different failure modes.

**Check:** you can name each resulting class before writing it, and none of the names needs an
"and".

---

## 2. The lazy write is the one to look for

```ruby
def call
  user = UserRecord.find(@id)
  user.touch(:last_seen_at)          # <- the write, in a query, in the middle
  ProfileShape.new(user)
end
```

`touch`, `update_column`, `increment!`, a counter cache, a "last accessed" stamp. **These are
the ones nobody notices**, because they are not what the method is about — and they are the
ones that make a read take a write lock under load.

They almost never belong to this operation at all. A `last_seen_at` stamp is a *different*
thing that happened to be convenient here; it becomes its own command, called by whatever is
actually responsible for the session.

**Check:** `QueriesOnlyRead` is silent, and the query's name still describes everything it does.

---

## 3. Sequence with a workflow, not a query

Once split, something has to run both. That is a workflow — the only kind obliged to accept
that it spans more than one transaction:

```ruby
class RegisterConsumerApp < Workflow
  def call
    found = FindConsumerApp.call(actor: actor, name: @name)
    return found if found.value

    CreateConsumerApp.call(actor: actor, name: @name)
  end
end
```

**Do not put the sequencing in a command.** A command calling a command has either nested a
transaction or silently widened one, and nobody decided which — `CallGraph` refuses it, and
`a-command-is-one-transaction` is why.

**Check:** `AggregationIsReadable` is silent, the workflow demands the union of its steps, and
`CallGraph` reports nothing new.

---

## 4. Make each step idempotent, because now it has to be

A workflow crosses transactions. The half-done state is now reachable: the find succeeded, the
create did not, the process died between them. **That state was always reachable** — the
single query just had no way to express it — but now it is your problem in writing.

For each step: if it runs twice, what happens? A `create!` that runs twice raises on a
uniqueness constraint, which is the right answer if the constraint exists and a duplicate row
if it does not. **This is where the unique index gets added**, and it is not optional.

**Check:** the index exists in `db/schema.rb`, and the step's test calls it twice.
`Shipshape/CommandsProveIdempotence` requires the test to say *how* — a sentence beginning
`Idempotent:` naming what makes the second run safe. It checks the sentence was written, never
that it is true, which is why the index above is a separate check and not the same one.

---

## 5. The writes this cannot see

`QueriesOnlyRead` needs a write rooted in a **record constant it can resolve**.
`PersonRecord.create!` and `PersonRecord.find(1).update!` are seen. These are not:

```ruby
person = fetch_person          # a local — no constant to read
person.update!(name: @name)

@invoice.touch                 # an ivar handed in
rows.each(&:save!)             # through a block
```

The generated `Shape` refuses to *hold* a record, which removes the commonest source of these
in the presentation layer — but a query holding one in a local is legal and invisible.

```sh
grep -rn "\.save!\|\.update!\|\.touch\|\.destroy" app/queries app/services
```

**Check:** the grep returns nothing in a query tree that the cop did not already name.

---

## What none of this proves

**Nothing here shows the caller still gets what it expected.** Splitting a
`find_or_create_by` query into two operations moves a decision to the call site, and every
call site now has to make it — including the ones that were relying on the create happening
silently.

The failure to expect: **a caller that assumed the row would exist afterwards.** It used to
create; now it finds nothing and answers `failure(:not_found)`, which is correct and is not
what the caller was written for. Only a test that exercises the caller's first-time path finds
that, and by definition it is the path least likely to be covered.
