# Decomposing inline IO — a network call is not a line in a method

A procedure, meant to be followed by an agent one step at a time. Every step ends with
something to **run**, because a decomposition nobody can verify is a rewrite with extra
confidence.

The shape, all four from real repositories:

```ruby
HTTParty.post(...)               # in an ActiveRecord model
Excon.get(...)                   # in a controller action
Net::HTTP.get(uri)               # in a job
Faraday.new { |b| ... }          # in a concern included everywhere
```

121 across seven repositories, and the count understates it: the cop knows the clients it is
told about, and every vendor SDK is invisible.

---

## 0. Find the ones the cop cannot

```sh
shipshape next --json
```

`IoIsItsOwnKind` names the standard library's networking and the common HTTP clients. **That
list is the fact, not a description of one** — a client not on it is invisible rather than
permitted. So before starting, add what this repository actually uses:

```yaml
Shipshape/IoIsItsOwnKind:
  Constants:
    - 'Stripe::Charge'
    - 'Aws::S3::Client'
    - 'Twilio::REST::Client'
```

```sh
grep -rn "Stripe\|Aws::\|Twilio\|Slack\|Sidekiq::Client" app lib | grep -v spec
```

**Check:** the offence count rises when you add the vendors. If it does not, either the repo
does not use them or the constants are spelled differently — find out which.

---

## 1. Read the transaction it is sitting in

Before moving anything, establish what the call is currently inside. This is the cost, and it
is what decides the urgency:

- **in a command** — a database transaction is open across the network round trip, including
  the far end's timeout and every retry underneath. Under load this is how a connection pool
  empties while every individual query looks fast.
- **in a query** — worse, because there is no transaction to blame and nothing about a read
  invites review.
- **in a record** — worst. A model that makes an HTTP call has put the network inside every
  `save`, including the ones in other people's transactions.
- **in a controller or a job** — no transaction, so the cost is only latency and coupling.

**Check:** for each site, you can say which of these it is.

---

## 2. Move the call, not the decision

```ruby
# before — one method, two responsibilities, one transaction
class SettleInvoice < Command
  def call
    response = HTTParty.post(gateway_url, body: payload)
    @invoice.update!(settled: response["ok"])
  end
end

# after — the crossing is its own operation
class ChargeCard < IoCommand
  def call
    success(HTTParty.post(@gateway_url, body: @payload))
  end
end
```

**The `IoCommand` does the call and nothing else.** Not the decision about what to do with the
answer, not the local write, not the retry policy. It crosses the boundary and reports what it
found — everything else is on this side and belongs to the workflow.

An `io_command` may not reach a record. The matrix refuses it, and the reason is this exact
temptation: an external write pulling from the local store is reaching back across the
boundary it just crossed.

**Check:** `CallGraph` is silent on the new class, which it will not be if the extraction
brought a record along.

---

## 3. Sequence with a workflow, and accept what that means

```ruby
class SettleInvoice < Workflow
  def call
    charged = ChargeCard.call(actor: actor, invoice_id: @id)
    return charged if charged.failure?

    RecordPayment.call(actor: actor, invoice_id: @id, reference: charged.value)
  end
end
```

**This is the step that changes the system, not just the file layout.** The two steps are now
two transactions, and the failure between them is expressible for the first time: the charge
went through, the row did not.

That state was always reachable. Written as one command it was reachable *and unnameable* —
the transaction rolled back the row and the network call stayed done, and nothing in the code
said so.

So: **the local step must be idempotent, and the remote one needs an idempotency key.** Every
serious payment API has one; using it is the difference between a retry that is safe and a
retry that charges twice.

**Check:** `AggregationIsReadable` is silent, the workflow demands the union of its steps, and the local step's
test calls it twice.

---

## 4. Records first, whatever the counts say

`app/models/channel/instagram.rb` calling `HTTParty.post` — a record with a network call
inside it — outranks everything else in this procedure regardless of how few there are.

`persistence-holds-no-behaviour` already refuses the method; this makes it urgent rather than
untidy. A callback that posts is the same defect with a trigger attached, and
[a callback web](a-callback-web.md) is the procedure for that half.

**Check:** `IoIsItsOwnKind` is silent on the record tree before you move on to the rest.

---

## 5. What the boundary buys, beyond the transaction

Worth stating because it is the argument for doing this at all when nothing is currently
broken:

- the call is **stubbable in one place**, so tests stop reaching the network by accident
- the timeout and the retry are **stated on one class**, not per call site
- `shipshape report` can count the crossings, because they are now a kind
- a workflow makes the partial failure **a state somebody chose**, rather than one that
  happens

**Check:** `shipshape check` — the count falls and never rises.

---

## What none of this proves

**Nothing here shows the retry is safe.** Splitting one command into a workflow makes the
partial failure reachable and *does not* make it correct. Every check above passes on a
workflow whose second step is not idempotent and whose first step has no idempotency key —
and that combination is strictly worse than the single command it replaced, because the
transaction is gone and nothing took its place.

That is the one judgement in this procedure that matters, and no tool makes it.
