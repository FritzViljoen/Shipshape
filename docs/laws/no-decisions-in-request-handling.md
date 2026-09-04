# `no-decisions-in-request-handling` — Request handling dispatches; it does not decide

An action parses its input at the seam, calls one or more operations, and chooses what to
render. It does not branch on domain state, reach for data, or work anything out.

**The rule is deciding, not counting.** One operation is the common case and the best case,
but an action calling three and examining none of their results has decided nothing. The
test is mechanical: does a result flow straight into another call, or does the action look
at it?

```ruby
CancelBooking.call(booking: FindBooking.call(id: id), reason: reason)   # resolving an
                                                                       # argument — fine

booking = FindBooking.call(id: id)
return redirect_to root_path if booking.cancelled?                     # deciding — not
CancelBooking.call(booking: booking)
```

**A workflow is optional.** It is what you reach for when a sequence has obligations worth
naming — it spans transactions deliberately, needs compensation, or runs from a job as well
as a request. Requiring one for every two calls would mean a `CancelBookingById` whose whole
body is find-then-cancel, one per action, and nobody writes the second one.

**This does not relax `deed` calling `deed`.** Two deeds called from an action are
visibly two transactions and nobody is pretending otherwise; a deed calling a deed
hides a widened one. The honest case stays allowed and the hidden case stays refused.

**And it is a trade, not a free win.** The count was crude but mechanical. "Decides nothing"
is the weakest guard here — the limit below says why — so relaxing the count leans harder on
the guard that cannot fully hold. Taken deliberately, because a rule people route around
teaches them the whole canon is routable.

**The line is between translating and deriving.** Rendering a value a reader can read —
formatting, localising, escaping — is translation, and belongs here. Deciding where it goes
— which template, what order, what grouping — is placement, and belongs here. Anything that
turns inputs into a **new value** is a rule, and a rule has one home.

**Branching is asking**, so a conditional on domain state in an action is a rule that has
escaped. The fix is to move the rule, not to tidy the conditional — often into an operation
that answers with the decision already made.

## A workflow is closer to a controller than to a deed, and this law reaches it

It sequences; it does not work. It opens no transaction of its own and it writes nothing, and
the only thing it is entitled to know about a step is whether the step succeeded.

So the same rule holds one level in: a workflow branches on `success?`, `failure?` or the
error code, and never on what the step answered with. `charge.value.total > 100` is a rule
about totals living in the sequence, where it applies to that one sequence instead of to every
caller of the operation that owns totals — and the next sequence will not have it.

**The law's name is about the case it was written for**, which was an action. The defect is the
same wherever a coordinator decides, and `tell-dont-ask` is the principle either way.

- **Principle:** `tell-dont-ask` governs. `good-boundaries-make-good-neighbours` also
  produces it — a decision made here is a rule outside its one home.
- **Guard:** `Shipshape/WorkflowsBranchOnOutcome`, over the workflow tree. Fails a condition
  that reads `value` off a step, and accepts `success?`, `failure?` and `error`.
  **A second cop rather than a wider `Kinds` list, and that was measured**: with `workflow`
  added to the cop below, all eight shapes tried came back clean — it keys on an instance
  variable being interrogated, because an action's subject is `@story`, and a workflow's is a
  local holding a `Result`. Teaching that cop about locals would fire on every action
  branching on something it parsed.
- **Guard:** `Shipshape/NoDecisionsInRequestHandling`, over the request-handling tree, fails
  a conditional whose test asks something of an instance variable — what the action is about
  to render — while allowing `result.success?` and its siblings, which is the decision
  arriving as a value. The **data-access half is held separately**, by
  `Shipshape/CallGraph`: request handling may not reach a record, because the matrix does not
  give it that edge.

  **Two conditions, and no others: `success?` and `present?`.** A deed answers an outcome
  and a question answers `nil`, a shape, or an array of shapes — so `present?` is correct across
  all three, and "did it find anything" has one spelling whether the question answers one or many.
  Every other test is a rule. `unless` and `!` are the same branch spelled differently and are
  allowed; **`respond_to do |format|` is how a format is chosen**, and it is a dispatch rather
  than a conditional, so it is untouched. `if request.xhr?` is not — `respond_to` names both
  outcomes, and a conditional names one and hides the other.
- **Guard's limit:** it reads the **condition**, so work done before it is invisible: an action
  may compute anything it likes and test `success?` on the result. `.present?` is `!blank?`, so
  a shape answering `empty?` would read as absent — that hole is closed from the other side by
  `Shipshape/PresenceIsNotRedefined`, not here.
- **Guard's limit:** **this is the weakest guard in the canon and it should be read as
  partial.** Telling a presentation conditional from a domain one is a judgement in the
  general case, and the cop does not attempt it: it fires on **any** message sent to an
  instance variable inside a condition, so `render :empty if @report.rows.empty?` is an
  offence and must be argued in review. **A decision it cannot resolve is not invisible —
  it is refused.** A condition on a local, a method call, or a plain value has no ivar for
  the cop to name, so it falls through to the blanket offence: `if booking.nil?` and
  `if booking.any?` are flagged the same as an untraced ivar send, with no way to spell
  "did it find anything" except `present?`. Views are not covered at all. `CallGraph` holds
  data access only for a **constant** receiver — `@person.update!` inside an action is
  caught by nothing.
