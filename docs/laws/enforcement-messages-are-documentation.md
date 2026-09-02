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

  Judgement needs a rule to exercise: a message may state what the guard inspected, and
  what to write instead. It may not state why the code came to be that way, and it may not
  assert a fact about a file, a class, or a mechanism it did not itself read at the point it
  fired.

  "The base class already opened one" held for two of the seven kinds the cop fires on and
  was wrong for the rest — a cause checked once and applied to every case. "The runtime
  guard cannot catch this one" named a second mechanism's current behaviour, and the very
  next commit made it false. `install` reporting a file as differing "from what the gem
  ships now" assigns a cause — staleness — to a diff that can just as well be a deliberately
  chosen flag; the guard compared two files and can name the diff, never why it exists. A
  generated rules file or a base class header naming a method no installed class defines is
  describing the template, not the file in front of the reader.
