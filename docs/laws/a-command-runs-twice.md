# `a-command-runs-twice` — Every command says what happens when it runs again

A command's test names what makes a second run safe. Not that it is safe — that it was
thought about, by whoever wrote it, while they still knew.

## It is not a new obligation; it is one `tell-dont-ask` already imposed

A caller may not ask whether the work has happened already. **Branching is asking**, and a
conditional at a call site is a rule that escaped its home. So the caller cannot guard the
call:

```ruby
# refused — the caller has taken a decision that belongs to the command
SettleInvoice.call(...) unless invoice.settled?
```

Which leaves the command owning repetition, whether or not anybody noticed. Every command in
every codebase following that principle is *already* obliged to be safe against a second call.
This law only makes somebody write down how.

## Deferral is what turns it from tidy into load-bearing

A queue retries. A command that double-applies turns one retry into two charges, and the retry
is not a rare path — it is the ordinary response to a timeout, a deploy, a worker restart.

**This is also why a deferred failure cannot simply raise.** Under this law a second run
answers *differently*: `success`, then `failure(:already_settled)`. That is correct for a
synchronous caller. If a deferred run raised on any failure, a retry meeting "already settled"
would raise, retry, and eventually dead-letter a job that had **succeeded**. The failure
taxonomy — done, transient, terminal — is the thing async needs, and it needs this law first.

## The append is the case that gets the least thought and needs the most

`SettleInvoice` can consult `settled_at`. `PostComment` cannot: two identical comments are both
legal, and there is nothing in the row to distinguish the second from an honest duplicate.
Tell-don't-ask makes it own the decision and hands it nothing to decide on.

So idempotence there is **a key, not a judgement** — a unique index, or an idempotency key from
the caller. That is a schema change, which is the honest reason it gets skipped, and it is the
same conclusion [`a-query-that-writes`](../decomposing/a-query-that-writes.md) and
[`inline IO`](../decomposing/inline-io.md) reach: the index is not optional.

- **Principle:** `tell-dont-ask`
- **Guard:** `Shipshape/CommandsProveIdempotence`, over `command`, `io_command` and
  `legacy_command`. Fails a command whose test file does not carry the words `Idempotent:`.
  Tests are found by file name across every declared test root, so a repository that files
  them by kind, by mirrored path, or flat is all one case.
- **Guard's limit:** **it checks that the claim was written, never that it is true.** A command
  whose test says "Idempotent: the unique index refuses the second row" passes with no such
  index, and a claim next to a test that calls the operation once passes as readily as one next
  to a test that calls it twice. This is the same position `a-guard-states-its-limit` takes
  about `Watched to fail`, taken for the same reason: writing the sentence is the act, the
  check makes the act compulsory, and no check makes the judgement.

  It finds tests by **file name**. A command exercised only from a shared example, a request
  spec covering four commands, or a differently-named file reads as untested — a false positive
  to be argued in review rather than suppressed in silence.

  It says nothing about workflows, whose steps carry the same obligation, and nothing about a
  command that is idempotent today and stops being so when a column is added.
