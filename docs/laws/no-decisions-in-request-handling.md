# `no-decisions-in-request-handling` — Request handling dispatches; it does not decide

An action parses its input at the seam, calls **one** operation, and chooses what to render.
It does not branch on domain state, reach for data, or work anything out.

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
