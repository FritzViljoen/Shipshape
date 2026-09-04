# Decomposing an untimed call — somebody else's outage, arriving as yours

A procedure, meant to be followed by an agent one step at a time. Every step ends with
something to **run**, because a decomposition nobody can verify is a rewrite with extra
confidence.

**What you are aiming at:**

```ruby
# both timeouts, because setting one leaves the other unbounded
Faraday.new(url: @endpoint) do |conn|
  conn.options.open_timeout = 2   # refusing to connect
  conn.options.timeout      = 5   # connected, and not answering
end
```

A call with no ceiling is a thread held for as long as the far end likes, and the far end has
no obligation to you. The second timeout is the one people forget, and it is the one that
matters when a host accepts the connection and then goes quiet.

The shape: `HTTParty.post(url, body: ...)` with no timeout. The supplier's endpoint stops
answering — not refusing, answering slowly — and every thread that touches it waits. The pool
fills, requests that never go near the supplier queue behind them, and the application is down
for a reason nothing in it caused.

**Nothing here is a shape defect, and that is the point.** The call is correct. What is missing
is a bound, and a bound has nowhere to live until the call has a home — which is what
[`io-is-its-own-kind`](../laws/io-is-its-own-kind.md) gives it. Once every outbound call is an
`io_deed` or `io_question`, "does this have a timeout" becomes a question with one place to ask
it per integration, instead of one per call site.

---

## 0. Find the calls, then find the ones outside the io kinds

```sh
grep -rn "Net::HTTP\|HTTParty\|Faraday\|RestClient\|\.get(\|\.post(" app lib | grep -v "app/io/"
```

**A call outside the io trees is the first finding and the bigger one.** It is
[inline IO](inline-io.md) — an HTTP call in the middle of a method, often inside a transaction
— and that procedure comes first. A timeout on a call that holds a database transaction open
converts one problem into a different one.

**Check:** every outbound call is in an `io_deed` or `io_question`, or is on the list for
[inline IO](inline-io.md).

---

## 1. Two timeouts, and only setting one is the usual mistake

```ruby
Faraday.new(url: @endpoint) do |conn|
  conn.options.open_timeout = 2   # refusing to connect
  conn.options.timeout      = 5   # connected, and not answering
end
```

**`open_timeout` alone is the common half-fix.** A host that accepts the connection and then
says nothing is the failure mode that hangs you, and it passes an open timeout every time. The
read timeout is the one that matters, and it is the one people leave at the library default —
which is frequently *no limit*.

**Check:** for each client, you can name both numbers. "The default" is not an answer until you
have looked it up; several popular clients default to infinity.

---

## 2. The number comes from what the caller can wait for

Not from what the endpoint usually takes. A request-cycle call has the user's patience as its
ceiling — a few seconds. A deferred one can afford more, because nobody is watching.

**Which means the timeout belongs to the operation, not to the client**, and an integration
called from both places has two callers with different budgets. That is two operations, or one
that takes its budget as a typed argument.

**Check:** each io operation states its timeout near its call, as a constant or an argument,
and the value has a reason you can say out loud.

---

## 3. A timeout is a failure, so it answers like one

```ruby
def call
  success(post_to_supplier)
rescue Faraday::TimeoutError
  failure(:supplier_unavailable)
end
```

**Not a rescue that returns nil.** `Shipshape/NoEmptyRescue` refuses that, and this is why the
rule exists: a timeout swallowed into `nil` is indistinguishable from a supplier that had
nothing to say, and the caller cannot retry what it cannot see failed.

**Check:** `Shipshape/NoEmptyRescue` is silent, and the operation's failure code names the
outside world rather than a Ruby exception class.

---

## 4. Bound the retries too, or the timeout made it worse

A timeout plus automatic retries is the same wait multiplied. Three retries on a five-second
timeout is a fifteen-second request, and against a struggling dependency it is your traffic
tripled at the moment it can least take it.

Retries belong to the deferred path — `ATTEMPTS` on the deed, which
[work in the request cycle](work-in-the-request-cycle.md) covers — and in the request cycle the
right number is usually zero.

**Check:** you can state the worst-case time for the request path, and it is a number the user
would tolerate.

---

## 5. Stop when every outbound call has a stated bound

```sh
shipshape check
```

---

## What this leaves you

**A dependency that can fail without taking the application with it.** A slow supplier becomes
a failed operation with a name, on a bounded clock, at a call site that can decide what to do
about it.

## What none of this proves

**A timeout is not a circuit breaker.** With a bound in place, a dead supplier still consumes a
thread for the full timeout on every request, and under load that is still enough to exhaust
the pool — slower, which buys time, and not indefinitely. Deciding to stop calling a dependency
that is failing is a separate mechanism and this canon has nothing to say about it.

**And nothing verifies the number.** A five-second timeout on a call that has never taken more
than 200ms is untested code: it has never fired, so whether the `rescue` works, whether the
failure code is handled, and whether the caller does something sensible are all unknown. Test
the timeout path deliberately with a stub that hangs — it is the branch most likely to be wrong
and least likely to be exercised.
