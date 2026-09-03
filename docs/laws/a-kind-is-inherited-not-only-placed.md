# `a-kind-is-inherited-not-only-placed` — Placement earns a file a kind; only inheritance earns a class its guarantees

```ruby
# app/commands/foo.rb
class Foo                                    # no superclass at all
  def call
    BookingRecord.find(1).update!(state: "x")
  end
end
```

`Foo` is `command` to all forty-some cops this gem ships. `Shipshape/OperationsOpenNoTransaction`
trusts it opens one. `Shipshape/TypedArguments` trusts its constructor asserts what it is
handed. `Shipshape/EveryDoorChecksPermission` trusts something checked who is calling. None of
that is true. `Foo` inherits `Object`.

**`Kinds#for_path` already says why, in its own comment: "the superclass decides the kind; the
path only decides which trees are governed at all."** That is correct as a description of
intent. It is not correct as a description of what the code does when a class names no
superclass, or names one this canon cannot resolve — `for_path` falls back to the path alone,
because a governed tree cannot simply become ungoverned the moment one file in it is wrong.
That fallback is the right failure mode for `Shipshape/CallGraph`, whose job is call-graph
coverage. It is the wrong one for every cop that reads `command` or `record` and assumes the
base class's own machinery is behind it, because none of them re-checks the assumption
`for_path` just made silently on their behalf.

**The inverse hole is the same defect from the other side.** A class at a path no glob
matches — `app/integrations/stripe/stripe_gateway.rb`, filed outside every `Kinds` entry —
gets no kind at all, so it is governed by nothing rather than governed hollow. Right path,
wrong inheritance is *governed and hollow*; wrong path is *not governed at all*. This law
closes only the first. The second is `shipshape coverage`'s business already — it counts
exactly these files — and deciding whether an `integration` kind belongs in `Kinds` at all is
a separate design question this law does not answer.

**Only the class the path itself names is held to this**, never every class a file happens to
contain. A file may hold a namespace module, a private helper class nested inside the real
one, a sibling class for an error the real one raises, a `Struct.new` block with no `class`
keyword at all. The one under judgement is the one whose fully-qualified name is what a
loader would resolve this exact file to — the identical name-to-path lookup
`an-operation-is-a-leaf`'s guard already uses to walk a superclass chain across files. Everything
else in the file resolves to some other name, or to nothing, and is left alone.

**A kind that declares no base in `BaseClasses` is skipped, not guessed at.** `shape`,
`record`, `view_component`, `entry_point` and `request_handling` all declare one today, and an
application is free to add a kind that never will — a legacy door wrapping a library with no
sensible shared ancestor, say. Guessing a base for a kind that named none would be inventing a
rule nobody wrote; skipping it is what leaves that kind classified by path alone, exactly as
`for_path` already treats it.

**The base class itself, filed inside the tree it governs, is exempt from needing to inherit
itself.** `an-operation-is-a-leaf` names the same shape already: a repository that keeps
`Command` at `app/commands/command.rb` is a legitimate layout, and `class Command` there
correctly declares no superclass. A class whose own name is one of its kind's declared bases
is the base, not a subject of this law.

- **Principle:** `make-the-wrong-thing-impossible` — a kind's guarantees are supposed to be
  encoded in a base class, not remembered by whoever names a directory; a cop that reads
  `command` off a path alone and trusts the rest is the "write it down and hope" this
  principle exists to replace.
- **Guard:** `Shipshape/KindIsInheritedNotOnlyPlaced`. For the one class a file's path
  resolves to, fails a superclass that is missing entirely, and fails one that resolves all
  the way to a real file — directly, or through a chain of superclasses this canon can trace
  on disk — whose own chain never reaches a name `BaseClasses` declares for that kind. A
  superclass this canon cannot resolve at all is left alone, not failed: unresolvable is not
  evidence of anything, and guessing from it would fail the gem's own installed base classes
  along with every gem base an application legitimately inherits.
- **Guard's limit:** it resolves a superclass exactly as `Shipshape/CallGraph` and
  `Shipshape/OperationsAreLeaves` do — a constant name turned into the path a loader would
  expect and looked up on disk — so everything their own guard's limits already name applies
  here too: `Class.new(Command)`, a superclass assigned through a constant or produced by a
  generating call, and any base whose file sits outside a tree this canon's `Kinds` declares —
  `app/shipshape/`, where this gem's own installed base classes are generated, is exactly such
  a tree — are invisible and left alone rather than failed. A class reopened later in the same
  file without repeating its superclass is judged again on that later statement, which names
  none — the guard has no memory of the earlier one.

  Base matching, on both sides, compares only the last `::` segment — the same convention
  `an-operation-is-a-leaf`'s guard uses — so `Vendor::Gubbins::Command` passes as `Command`,
  and a local `module Reports; class Command; end` buys itself the exemption `Command` itself
  gets, over-firing silently wherever two modules share a last segment.
  `ApplicationCable::Connection < ActionCable::Connection::Base` is accepted today only
  because both names end in `Base`.

  Resolving a superclass from source also reads the **first** `class NAME < SUPER` line in
  the target file, not the one naming the constant actually being resolved: a file that opens
  with an unrelated exception ahead of the class the loader would really resolve —
  `class UserError < StandardError` before `class User < ApplicationRecord` — hands back
  `StandardError` as `User`'s superclass. Left as the existing convention rather than fixed
  here: correcting it needs its own name-aware match across every class in a file, which is a
  second way to ask a question `Kinds#for_path`'s own ambiguity check and
  `Shipshape/OperationsAreLeaves`'s depth check still ask the first way — fixing it for this
  guard alone would make one file's superclass depend on which cop asked.

  This law does not reach the inverse hole: a file no `Kinds` glob matches gets no kind and
  is invisible to every cop here, this one included; `shipshape coverage` is what counts that
  gap today.
