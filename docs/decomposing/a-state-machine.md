# Decomposing a state machine — the status column is a denormalisation

A procedure, meant to be followed by an agent one step at a time. Every step ends with
something to **run**, because a decomposition nobody can verify is a rewrite with extra
confidence.

**What you are aiming at:**

```ruby
# the act writes an event; the state is derived from what happened
class DeliverEmail < Write
  def call
    return failure(:not_active) unless @email.active?

    success(DeliveryRecord.create!(email_id: @email.id, at: @now))
  end
end

class EmailState < Read
  def call = state_of(@email)   # reads the events, answers a shape
end
```

"Why is this delivered?" then has a row as its answer, with a time and an actor — instead of
"because the column says so and nobody knows who set it."

A `status` column, a gem that declares transitions, and branches all over the codebase that
read it. `draft → active → delivered → archived`.

**The status column is almost always a denormalisation of events that already happened.**
`delivered` means a delivery row exists. `archived` means somebody archived it, at a time,
for a reason. The column is a cached answer to a question the data can already answer — and
like every cache, it goes stale, disagrees with the rows, and nobody can say which is right.

---

## 0. Make the tree visible

```sh
shipshape coverage
```

---

## 1. Write down what each state means in terms of rows

Before touching code. For each state, finish the sentence *"this is true when …"*:

| State | True when |
|---|---|
| `draft` | no `published_at` |
| `active` | `published_at` set, no `delivered_at` |
| `delivered` | a delivery row exists |
| `archived` | an `archived_at` |

**If a state cannot be finished that way, it is a real fact and needs its own row** — that is
the discovery, and it is common. A state nobody can derive is a state somebody set by hand,
and the transition that set it is missing from the model.

**Check:** every state has a right-hand side, or a new row is named.

---

## 2. Move the transitions to rows

A transition table — `from`, `to`, `who may`, `what it requires` — is data. Declared in a DSL
it is code, so adding a state is a deploy and no tenant can differ.

**This is the step that stops the growth.** The branches multiply because the *states* do.

**Check:** "Rules that are really data" falls; the `case status` chains go.

---

## 3. Each transition becomes a write

```ruby
class DeliverEmail < Write
  def call
    return failure(:not_active) unless @email.active?
    success(DeliveryRecord.create!(email_id: @email.id, at: @now))
  end
end
```

One transition, one write, one transaction, named by what it does. **The guard is inside
the write**, not a callback and not a validation — it is the first thing `call` does, and
it answers `failure(:code)` so the caller can act.

Where a workflow sequences several,
[`a-permission-is-the-class-name`](../laws/a-permission-is-the-class-name.md) applies: what it
reaches is read out of `call`, and it is refused whole before the first step runs.

**Check:** `Shipshape/NoCallbacks` is silent — no transition happens because something was
saved.

---

## 4. The state becomes a read

```ruby
class EmailState < Read
  def call = success(state_of(@email))
end
```

Derived from the rows, in one place, so nothing else in the codebase reads the column and
branches. If deriving is too slow, **then** cache it — in a suffixed cache table, written by
a scheduled write that is idempotent, and understood as a cache rather than as the truth.

That ordering matters: the column comes back only after the derivation exists, so there is
always something to check the cache against.

**Check:** `Shipshape/NoDecisionsInRequestHandling` is silent — no controller reads a status
and decides.

---

## 5. Stop when the count stops falling

```sh
shipshape check
```

---

## What this leaves you

**Every state is explicable.** "Why is this delivered?" has a row as its answer, with a time
and an actor, instead of "because the column says so and nobody knows who set it."

## What none of this proves

Whether a state is worth deriving at all. Some are genuinely a single flag somebody flips,
and modelling three tables to avoid one boolean is the opposite mistake. The test is whether
anyone has ever asked *when* or *who* — if they have, the event is the fact and the column is
the cache.
