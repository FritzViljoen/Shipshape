# Decomposing a swallowed error — turning a silence into an answer

A procedure, meant to be followed by an agent one step at a time. Every step ends with
something to **run**, because a decomposition nobody can verify is a rewrite with extra
confidence.

The shape:

```ruby
def charge
  gateway.charge(@amount)
rescue StandardError
  nil
end
```

673 of these across seven repositories. **Every one is a decision somebody made and did not
write down** — the caller gets `nil`, and `nil` now means "it worked and there was nothing to
return", "it failed and we chose to continue", and "something we never thought about happened",
with no way to tell which.

**What you are aiming at:**

```ruby
# before — three outcomes, one branch, and the reason is gone
charge = ChargeCard.new(amount).call
redirect_to failed_path unless charge

# after — the failure carries a code the caller can act on
result = ChargeCard.call(actor: current_user, amount_cents: amount.cents)
return redirect_to failed_path, alert: t(result.error) if result.failure?
```

An expected failure comes back as a value with a name. A defect raises, because a Result is
not a place to put a bug — and a swallowed one is neither.

---

## 0. Read what the rescue is actually catching

```sh
shipshape next --json
```

`NoEmptyRescue` names each one. Before changing anything, answer one question per site, and
the answer is one of exactly three:

| What it is | What it becomes |
|---|---|
| an **expected** failure of this operation | `failure(:code)` — a value |
| a failure of something **below** this operation, that this one can genuinely proceed without | a rescue that says so, narrowly typed, with the reason in a comment |
| **nobody knew**, and the rescue was armour | delete it and let it raise |

**The third is the commonest and the hardest to admit.** A bare `rescue StandardError` around
four lines was almost never a decision about those four lines; it was written once when
something failed in production and has been catching everything since.

**Check:** you can say, for each site, which of the three it is, before editing any of them.

---

## 1. Name the expected failures first

An expected failure is part of what the operation is *for*: an invoice already settled, a
booking whose window closed, a card declined. These are not exceptions — they are outcomes,
and `an-operation-answers-a-result` says so.

```ruby
# before
def call
  @invoice.settle!
rescue ActiveRecord::RecordInvalid
  nil
end

# after
def call
  return failure(:already_settled) if @invoice.settled?

  @invoice.settle!
  success(@invoice.id)
end
```

**The guard clause replaces the rescue.** If the condition can be asked before the attempt,
ask it — a rescue used as a conditional hides the condition, and the next reader cannot find
out what makes this fail without reading the callee.

**An error code is a name, never a sentence.** `failure(:already_settled)`, not
`failure("Invoice 12 has already been settled")`. The generated `Result.failure` refuses
anything but a Symbol, so this one is held by the architecture rather than by review.

**Check:** the operation's own tests assert `result.error` for each named failure. `Result`
raises at construction if a sentence is passed.

---

## 2. Narrow the ones that stay, and say why

Some rescues are legitimate: a cache read that may fail, a metrics call nobody should die for.
Two things make them legal — a **specific** exception class and a **written reason**:

```ruby
# rubocop:disable Shipshape/NoEmptyRescue
# The metrics endpoint is best-effort by design: a settlement must not fail because the
# dashboard is down. Verified 2026-08-30 — the client already retries twice internally.
rescue Metrics::Unavailable
  nil
end
# rubocop:enable Shipshape/NoEmptyRescue
```

`rescue StandardError` is never one of these. It catches `NoMethodError`, which is your typo,
and it catches the failure you have not met yet.

**Check:** `NoEmptyRescue` is silent, and every suppression names an exception class and gives
a reason a reader can disagree with.

---

## 3. Delete the armour

The third category. Let it raise, and find out.

**This is the step that feels dangerous and is not.** An exception that reaches the top is a
report; a rescue that swallowed it is the same failure with the report deleted. The
information was always being lost — deleting the rescue only stops hiding that.

Do it in a slice small enough to watch. If a bare rescue was catching something real, you will
learn what within a day, and then it is one of the first two categories and gets treated as
such.

**Check:** `shipshape check` — the count falls. Then watch the error reporter, which is the
actual check and does not live in this repository.

---

## 4. Fix the callers the silence was protecting

A caller written against `nil`-means-anything usually has a matching silence:

```ruby
# before — three outcomes, one branch
charge = ChargeCard.new(amount).call
redirect_to failed_path unless charge

# after
result = ChargeCard.call(actor: current_user, amount_cents: amount.cents)
return redirect_to failed_path, alert: t(result.error) if result.failure?
```

**A `Result` is truthy whether it succeeded or failed**, so `if result` is true for both — the
one mistake this migration reliably produces. It is green in Ruby and wrong at runtime.

**Check:** grep the call sites for `if result` and `unless result`; every one should be
`result.success?` or `result.failure?`.

---

## What none of this proves

**Nothing here shows you classified correctly.** A failure you called expected and returned as
`failure(:x)` is indistinguishable, to every check here, from one you should have let raise.
The count falls either way.

The judgement is: **would a person want to be told?** An already-settled invoice, no. A
database that is gone, yes — and turning that into `failure(:unavailable)` is the same silence
wearing a `Result`, which is worse than the bare rescue because it now looks handled.
