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

**This does not relax `command` calling `command`.** Two commands called from an action are
visibly two transactions and nobody is pretending otherwise; a command calling a command
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

- **Agreed:** grandfathered — predates this record, and its provenance is the repository's early history rather than a decision anybody can now point at.
- **Principle:** `tell-dont-ask` governs. `good-boundaries-make-good-neighbours` also
  produces it — a decision made here is a rule outside its one home.
- **Guard:** `Shipshape/NoDecisionsInRequestHandling`, over the request-handling tree, fails
  a conditional whose test asks something of an instance variable — what the action is about
  to render — while allowing `result.success?` and its siblings, which is the decision
  arriving as a value. The **data-access half is held separately**, by
  `Shipshape/CallGraph`: request handling may not reach a record, because the matrix does not
  give it that edge.
- **Guard's limit:** **this is the weakest guard in the canon and it should be read as
  partial.** Telling a presentation conditional from a domain one is a judgement in the
  general case, and the cop does not attempt it: it fires on **any** message sent to an
  instance variable inside a condition, so `render :empty if @report.rows.empty?` is an
  offence and must be argued in review. In the other direction, a decision on a local, a
  method call, or a plain value it cannot trace is invisible, and views are not covered at
  all. `CallGraph` holds data access only for a **constant** receiver — `@person.update!`
  inside an action is caught by nothing.
