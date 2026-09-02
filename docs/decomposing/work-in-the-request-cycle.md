# Decomposing work in the request cycle — the caller is waiting for something they do not need

A procedure, meant to be followed by an agent one step at a time. Every step ends with
something to **run**, because a decomposition nobody can verify is a rewrite with extra
confidence.

**What you are aiming at:**

```ruby
# before — the caller waits for the email
SendConfirmation.call(actor: actor, order_id: order.id)

# after — the caller does not
SendConfirmation.call_later(actor: actor, order_id: order.id)
```

One write, one transaction, one job — the grain at which a retry is safe, which
`a-write-runs-twice` is what makes harmless. `success(:enqueued)` means accepted, not done.

The shape: creating an order sends a confirmation email, posts to an analytics endpoint,
rebuilds a cache and writes a PDF — all before the response. The user waits for four things
they cannot see, and any one of them failing loses the order.

**With the operation shape in place this is nearly free to fix**, which is the reason it is
worth a procedure: `call_later` defers any write
([`deferral-is-one-write`](../laws/deferral-is-one-write.md)), so the mechanics are one
word. **All the difficulty is in deciding what may be deferred**, and that is a judgement the
word makes it easy to skip.

---

## 0. Find the operations a request runs

```sh
shipshape edges
```

Then read each edge's `call` and list what it invokes. The candidates are the steps after the
one the response depends on.

**A `transaction do` is the boundary that matters here.** Everything inside it is the act; work
after the commit is usually the deferrable part, and work *inside* it that talks to the outside
is [inline IO](inline-io.md) and more urgent than this.

**Check:** for each edge, you can write the ordered list of operations it runs and mark which
one produces the response.

---

## 1. Ask what the response is allowed to promise

For each step after the response-producing one:

| Question | If yes |
|---|---|
| Does the response **show** its result? | it stays. A user reading a total cannot be told it is coming |
| Does a later request **depend** on it having happened? | it stays, or the later request must handle its absence |
| Is it visible to somebody else, later? | defer it |
| Is it for us — analytics, cache warming, indexing? | defer it |

**The second row is where this goes wrong.** Deferring the write that the next page reads
produces a redirect to a page showing nothing, intermittently, on a fast click. That is not a
race the queue introduced — it was always there — but deferring widens it from microseconds to
seconds.

**Check:** every step has an answer, and the deferred ones do not include anything the next
page reads.

---

## 2. Defer it, and the shape does the rest

```ruby
# before: the caller waits for the email
SendConfirmation.call(actor: actor, order_id: order.id)

# after: the caller does not
SendConfirmation.call_later(actor: actor, order_id: order.id)
```

**The arguments are typed and the actor is found again by id**, which is why this is safe here
and dangerous in an ordinary Rails app: nothing serialises a record, because
`Shipshape/TypedArguments` refuses one at construction. "Passing AR objects to jobs" is a row
on every list of Rails failures and it is unsayable in this shape.

**Check:** `shipshape check` is silent, and the deferred write's arguments are all primitives
or shapes.

---

## 3. It will run twice, so prove it can

A queue retries. A deploy interrupts a worker mid-job and the job comes back. **A deferred
write that is not idempotent is a defect the moment it is deferred**, and the guard already
demands the proof:

```sh
bundle exec rubocop --only Shipshape/WritesProveIdempotence
```

`Shipshape/WritesProveIdempotence` requires every write's test to say what happens on the
second run. Deferring one whose test does not is the point at which that requirement stops
being paperwork.

**Check:** the write's test runs it twice and asserts the second run's effect, and the answer
is one you would accept in production — not "it sends two emails".

---

## 4. Decide what the user sees when it fails

The request succeeded and the work did not. Somebody has to be able to find out.

Every operation records to the audit log, failures included
([`every-operation-reports-what-it-did`](../laws/every-operation-reports-what-it-did.md)), so
the trail exists. What does not exist by default is anybody looking at it.

**And retries are bounded per write**, by `ATTEMPTS` on the installed job — an unbounded
retry against a broken dependency is a queue hammering an outage into a longer one.

**Check:** the write declares its `ATTEMPTS`, and you can name where a permanent failure
surfaces.

---

## 5. Stop when the response waits only for what it shows

```sh
shipshape check
```

---

## What this leaves you

**A response whose time is the work it reports on**, and background work that can fail, retry
and be found afterwards without taking the request with it.

## What none of this proves

**Nothing here measures the request.** Which step was actually slow is an APM question, and
deferring the wrong one is a change that reads as an improvement and is not. Measure before
choosing, or you have moved the cheapest step off the critical path.

**And deferral makes a failure quieter, which is the trade.** In the request, a broken email
server was an error somebody saw immediately. In a queue it is a job that retried five times
overnight, and the difference between those two is whether anybody reads the audit trail. This
procedure moves the failure; it does not remove it, and it makes noticing somebody's job.

**Ordering is not preserved.** Two writes deferred in sequence run in whatever order the
queue gives them. If one depends on the other, they are one workflow with one deferral at the
front, not two independent jobs — and nothing here checks that you got that right.
