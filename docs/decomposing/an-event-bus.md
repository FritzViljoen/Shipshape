# Decomposing an event bus — callbacks with a gem in front

A procedure, meant to be followed by an agent one step at a time. Every step ends with
something to **run**, because a decomposition nobody can verify is a rewrite with extra
confidence.

The shape: `publish(:order_created, order)`, a `wisper` or `rails_event_store` or
`dry-events` in the Gemfile, and forty subscriber registrations in an initializer nobody opens.

**This is usually the second attempt.** A team meets callback hell, correctly diagnoses that
`after_save` is the problem, and moves the trigger off the record and onto a bus. Every property
that made callbacks bad survives the move: work happens because something *happened* rather than
because somebody asked, the order is registration order, the failure is attributed to the
publisher, and a reader following a call arrives at `publish` and stops. What is added is a gem
and a registry file.

[`nothing-travels-off-the-call-path`](../laws/nothing-travels-off-the-call-path.md) names it
exactly — "publishing to a subscriber list resolved at runtime" — and
[a callback web](a-callback-web.md) stops at its edge, calling it "a different defect with the
same shape". This is that defect.

---

## 0. Decide which of two things you have, because only one of them is this

**Real event sourcing**: the events *are* the source of truth, and current state is a fold over
them. Delete the event log and you have lost the data. That is a legitimate architecture with
costs its owners chose, and this procedure is not about it.

**Events as notification**: state lives in tables, the events describe what already happened to
those tables, and deleting the log loses an audit trail at worst. That is a bus bolted onto a
CRUD application, and it is what this walks back.

```sh
grep -rn "publish\|broadcast\|subscribe\|\.on(" app lib config/initializers
grep -rn "wisper\|rails_event_store\|dry-events\|ActiveSupport::Notifications" Gemfile app lib
```

**Check:** you can answer, in one sentence, what is lost if the event log is dropped. "The
audit trail" means notification. "Everything" means event sourcing — stop here.

---

## 1. If you wanted a record of what happened, you already have one

The commonest honest reason for adopting a bus is observability: somebody wanted to know what
the system did. Every operation already records to the audit log — the operation, the actor, the
outcome, the error
([`every-operation-reports-what-it-did`](../laws/every-operation-reports-what-it-did.md)) — and
it does it without a subscriber, a gem or an ordering.

**Check:** for each event you publish, say whether anything subscribes to it or whether it is
there to be read later. The second kind is deleted, not moved.

---

## 2. Build the ordering, because it is the thing nobody has written down

For each event, list its subscribers **in registration order**, which is the order they run and
is a property of an initializer rather than of the domain.

| Event | Subscribers, in order | What each does |
|---|---|---|
| `order_created` | `SendConfirmation`, `IndexOrder`, `NotifySupplier` | … |

**This table is the decomposition.** Once it exists the rest is mechanical, and until it exists
nobody can say what publishing does.

**Check:** the table is complete, and you have found the subscribers registered somewhere other
than the initializer — a gem's engine, a `to_prepare` block, a test helper.

---

## 3. The publisher becomes a workflow, and the subscribers become its steps

```ruby
# before — the caller says what happened and hopes
def call
  order = OrderRecord.create!(...)
  publish(:order_created, order)
  success(order)
end

# after — the caller says what it wants to happen, all of it
class PlaceOrder < Workflow
  def call
    order = CreateOrder.call(actor: actor, ...)
    return order if order.failure?

    SendConfirmation.call(actor: actor, order_id: order.value.id)
    IndexOrder.call(actor: actor, order_id: order.value.id)
  end
end
```

**There is no "also".** A consequence becomes a named step, and the sequence is the thing with a
name — which is what [a callback web](a-callback-web.md) says once the trigger is gone.

Where a consequence varies per tenant, the three placements in that procedure's step 3 apply
unchanged: make it anonymous, let it no-op convergently, or write two workflows.

**Check:** the greps from step 0 return one fewer publisher, and the workflow names in `call`
what that publisher used to broadcast.

**No cop counts a bus**, so nothing here goes from red to green: `NoCallbacks` reads a closed
list of ActiveRecord macros and `NoDistantWrites` reads assignment, and neither sees `publish`.
The law forbids it and no guard holds it — the count you are working against is the grep, and
this procedure will not tell you when you are finished.

---

## 4. Asynchronous subscribers become deferred commands, one job each

A bus that delivers in a background job is doing two things at once — decoupling and deferring
— and only the second was worth having.

`call_later` defers **one command, one transaction, one job**
([`deferral-is-one-command`](../laws/deferral-is-one-command.md)), so a retry re-runs exactly
one transaction. A subscriber list delivered as one job retries all of them, including the ones
that already succeeded.

**Check:** each deferred step is its own command, and
`Shipshape/CommandsProveIdempotence` is silent — a queue retries, and it will.

---

## 5. An event with an outside consumer is an integration, not a subscriber

If another service consumes the event, it is not yours to delete. It becomes an explicit
outbound call: an `io_command`, on the call path, with a timeout
([an untimed call](an-untimed-call.md)) and a failure the caller can see.

**Check:** every remaining publish either has a named outside consumer or is on the deletion
list.

---

## 6. Delete the registry, then the gem

In that order, and never the reverse. With the initializer gone the gem is unreferenced, and
removing it is a Gemfile line rather than an archaeology exercise.

```sh
grep -rn "wisper\|rails_event_store\|dry-events" app lib config   # must be empty
bundle remove wisper
```

**Check:** the suite is green with the gem removed, and the greps from step 0 return nothing.
`shipshape check` will not move — no cop counted the bus on the way in, so none counts its
removal.

---

## What this leaves you

**A caller you can follow.** What happens when an order is placed is a list in one file, in the
order it runs, with a name — and one fewer dependency, one fewer initializer, and one fewer
place where work is registered rather than called.

## What none of this proves

**Decoupling was sometimes the point, and this removes it.** A bus lets a subscriber be added
without touching the publisher, which is exactly why it accumulated forty of them and exactly
why nobody could say what publishing did. If a team genuinely needs to add consequences without
editing a sequence, that is a product requirement — and the honest shape for it is data the
workflow reads, not a registry the workflow cannot see.

**And no guard holds any of this.** `nothing-travels-off-the-call-path` forbids publishing to a
subscriber list, and its cops read ambient reads and assignment shapes — not `publish`. Every
step above is checked by a grep you run yourself, which is weaker than the rest of this playbook
and is said here rather than implied.

**Nothing here finds a subscriber registered at runtime, either.** `subscribe` called from a
conditional, a gem registering on your behalf, a test helper that registers and never
unregisters — the grep in step 0 sees registration syntax, not behaviour, and a bus whose
wiring is computed is a bus this procedure will leave half-dismantled.
