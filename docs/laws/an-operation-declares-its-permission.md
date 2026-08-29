# `an-operation-declares-its-permission` — Every command and query names the permission it needs, in the file

One line, greppable, at the top of the class. Not derived from the class name, not supplied
by a base class, not implied by where the file sits.

**Authorisation is a decision, so it belongs in the operation.** Request handling places what
an operation answered and decides nothing
([`no-decisions-in-request-handling`](no-decisions-in-request-handling.md)), so a permission
check in a controller is the rule living in the one file nobody greps for rules. The
operation knows what it is about to do; it is the only thing that does.

**The actor arrives as an argument, asserted like any other.** `current_user`, `Current.user`
and a thread local are ambient reads
([`nothing-travels-off-the-call-path`](nothing-travels-off-the-call-path.md)) — the caller
knows who is calling, the operation does not, and an operation that reaches for the actor
behaves differently in a job than it does in a request.

**Refusal is an expected failure, so it comes back as a value.** `failure(:forbidden)`, not a
raise: a raise is for a defect, and being told no is not a defect
([`no-silent-coercion`](no-silent-coercion.md)). The action then branches on
`result.success?` like it does for every other outcome, and permission stops being a special
case in the one place special cases are most expensive.

**Ask for a named permission, never for a role.** `@actor.may?(PERMISSION)` is one question
with one answer. `@actor.admin?` is a dispatch on what kind of thing the actor is, which is
[`no-type-interrogation`](no-type-interrogation.md), and it puts the permission model in
every call site instead of in one.

## Why a declaration rather than a base class or a name

**A base class that checks before dispatching to `call` is a lifecycle callback.** The caller
reads one method and gets two, in an order nothing states, with the refusal attributed to the
operation rather than to the check — which is precisely what
[`no-lifecycle-callbacks`](no-lifecycle-callbacks.md) forbids on a record. It is no better
here for being ours.

**A permission derived from the class name is a private convention.** It has a corpus of one
repository, so every reader re-derives it from source
([`code-is-written-not-generated`](code-is-written-not-generated.md)) — and it changes
silently under a rename, which is exactly the moment a permission must not change silently.

**A declaration cannot be forgotten, because the build refuses.** That is the difference
between a rule and a hope, and it is the whole of
`make-the-wrong-thing-impossible`.

```ruby
class SettleInvoice < Command
  PERMISSION = :settle_invoice

  def initialize(actor:, invoice_id:)
    @actor = typed(actor, Actor)
    @invoice_id = typed(invoice_id, Integer)
  end

  def call
    return failure(:forbidden) unless @actor.may?(PERMISSION)

    success(InvoiceRecord.find(@invoice_id).settle!)
  end
end
```

**Sizing is the other half of this rule, and it lives in
[`one-operation-one-class`](one-operation-one-class.md):** an operation is sized so it can be
permitted or refused whole. An operation spanning two permissions has nowhere to put the
refusal — it checks halfway through and leaves the first half done, or it takes the wider of
the two permissions and quietly grants the narrower one.

- **Principle:** `nothing-crosses-unasserted` governs — permission is a fact about the call
  that must be stated where the call is served. `nothing-is-hidden` produces the
  declaration-not-base-class half, and `make-the-wrong-thing-impossible` produces the guard.
- **Guard:** `Shipshape/OperationDeclaresPermission`, over the operation kinds. Fails a
  command or query with no `PERMISSION` constant. The name is configurable, and the kinds it
  covers are too — an application with genuinely unauthenticated operations narrows the list
  rather than suppressing the cop file by file.
- **Guard's limit:** it checks the declaration **exists**, never that the permission named is
  the right one, and never that `call` actually consults it — `PERMISSION = :settle_invoice`
  on a class that never reads it passes. It cannot see a permission model at all. Whether the
  operation is sized to one permission is the judgement in
  [`one-operation-one-class`](one-operation-one-class.md), and no check makes it. Workflows
  are outside the default list: a workflow sequences operations that each declare their own,
  and requiring a permission there would state one fact twice.
