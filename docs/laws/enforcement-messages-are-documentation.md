# `enforcement-messages-are-documentation` — An offence says what is wrong, why, and what to write instead

Three parts, in every message a guard produces. Not the rule's name. Not "avoid this".

**The failure is where a rule is actually delivered.** The law files in this folder are read
once, by whoever installs the gem. The message is read by everyone the rule ever stops, at
the moment they are stopped, which is the only moment they want it. A codebase's real
documentation is whatever its build says when it goes red.

**For an agent the message is the whole context.** It has no memory of the session that
wrote the rule, no design document open, and no colleague to ask. Whatever the message does
not say is not known — so an agent handed "Style/Foo: avoid this" does the one thing that
reliably makes the failure go away, which is to write something else that is also wrong, or
to add an inline disable.

**A message that only says something is wrong leaves two options, neither of them the
rule:** guess, or switch the cop off. Teams switch the cop off. That is how a guard survives
in the config while enforcing nothing, and it is the failure
[`a-guard-states-its-limit`](a-guard-states-its-limit.md) is about from the other side.

The example matters as much as the reason. A reason without an example is an argument the
reader has to finish; the example is what gets copied, and copying it is the outcome the
guard wants.

- **Agreed:** "the gaurds need to say the why and also give a good example, so agents get context from the failure".
- **Principle:** `nothing-is-hidden` governs — a rule enforced but not stated is hidden at
  the moment it matters most. `make-the-wrong-thing-impossible` produces the mechanism:
  `Explains#explain` takes all three parts as required arguments, so a compliant message is
  the easiest one to write.
- **Guard:** `Shipshape/EnforcementMessagesAreDocumentation`, over every file that calls
  `add_offense` — this gem's cops and the application's alike. Fails a message constant or
  an inline `message:` that lacks the `WHY:` and `INSTEAD:` sections.
- **Guard's limit:** it reads **literals**, and it checks for **sections, not sense**. A
  message assembled by a helper it cannot evaluate is passed — which is deliberate, because
  a cop that fires on code it cannot read gets disabled wholesale, and routing messages
  through `explain` makes the shape structural instead. It will never tell you the example
  is wrong, the reason untrue, or the whole thing stale. That is the author's judgement, and
  no check will ever make it.
