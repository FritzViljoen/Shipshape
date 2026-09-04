# `an-operation-answers-a-result` — Every door answers one shape, and a failure is a value

A deed, a workflow and the legacy doors answer with a `Result`: `success(value)`,
`failure(:code)`, or `failure(:code, value)` where the caller needs to know what was wrong. A
question answers with shapes and no envelope, because a read that found nothing found nothing —
that is an answer, not a failure.

**A failure is a value, not an exception.** An expected failure is part of what the operation
is for: an invoice that cannot be settled twice, a booking whose window has closed. Raising
for those makes the caller's ordinary path an exception handler, and an exception carries no
type — every caller invents its own idea of what may come back. A `Result` is one shape, and
the call site reads the same everywhere.

**A failure may carry what was wrong**, and the commonest reason is a form: a code alone
cannot re-render one. The value obeys the same rule everything a shape holds obeys — **it may
not be a record** — so what comes back is the fields and the messages as a shape, and the
presentation layer still never holds an ActiveRecord object. See
[a form that fails](../decomposing/a-form-that-fails.md).

**An error code is a name, not a sentence.** `failure(:already_settled)` is something a caller
can branch on and a translator can render. `failure("Invoice 12 was already settled")` is a
string that has to be parsed to be used and re-parsed when the wording changes.

**The uniform answer is what makes a wrapper possible at all.** Logging, instrumentation, an
audit trail, a migration seam — each of those is one place only because every door answers the
same way. Four return conventions and none of them can exist.

**This is not checked after the fact; it is made true at the door.** The generated base class
asserts the return type of every call and raises `TypeError` when a subclass answers with
something else. A subclass cannot quietly teach its callers a second shape, because the run
stops rather than the shape spreading.

- **Principle:** `nothing-fails-quietly`
- **Guard:** the generated `deed.rb`, `workflow.rb`, `io_deed.rb`, `legacy_deed.rb`
  and `result.rb` — architecture rather than a cop. `self.call` asserts `result.is_a?(Result)`
  and raises `TypeError` naming the class and what it answered with. `Result.failure` refuses
  anything but a Symbol for the code, so an error sentence cannot be smuggled in as one, and
  `Shape` refuses a record, so a failure cannot carry one back. Proven by
  `generated_base_classes_test.rb`, which is a listed suite guard.
- **Guard's limit:** it is a runtime assertion, so it fires when the path runs rather than when
  the code is written — a branch no test covers answers wrongly until something takes it. It
  says nothing about whether the value inside a `success` is the right one, and nothing about a
  question, which answers shapes and has no envelope to assert.
