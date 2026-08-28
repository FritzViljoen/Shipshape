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

- **Principle:** `tell-dont-ask` governs. `good-boundaries-make-good-neighbours` also
  produces it — a decision made here is a rule outside its one home.
- **Guard:** `Shipshape/NoDecisionsInRequestHandling`, over the request-handling tree. Fails
  data access outright, and fails a conditional whose test reads a domain object.
- **Guard's limit:** **this is the weakest guard in the canon and it should be read as
  partial.** Telling a presentation conditional from a domain one is a judgement in the
  general case; the cop can only hold a closed list of receivers it recognises as domain
  objects, so a decision made on a plain value it cannot trace is invisible. Views are not
  covered at all. Until that changes, the branching half of this law is held by review, and
  the data-access half is the part the build actually holds.
