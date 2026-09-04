# `nothing-travels-off-the-call-path` — Nothing enters but arguments; nothing changes but what was handed in

An operation reads what it was given and changes what it was given. Nothing arrives by
another route, and nothing is altered that the caller cannot see from the call.

**Forbidden entering** — an ambient read: the current time or zone, a current-user or
request-scoped global, a thread local, an environment variable, a setting fetched
mid-operation. The caller knows where it is running; the operation does not, and must not
guess.

**Forbidden leaving** — a distant write: assigning a global or a class-level attribute,
mutating a constant, reopening another class, publishing to a subscriber list resolved at
runtime.

**These are one defect facing opposite ways** — a dependency that is not on the call path.
Action at a distance is the leaving half, and nothing else in this canon catches it: the
cause is perfectly visible, and it is the *effect* that cannot be found by reading.

- **Principle:** `good-boundaries-make-good-neighbours`
- **Guard:** `Shipshape/NoAmbientReads` and `Shipshape/NoDistantWrites`, over the operation,
  value, view-component and legacy-door trees.

  **A legacy door is new code**, and takes what it was given like every other kind — only the
  world on the far side of it is old. The doors were outside both cops until the kinds were
  audited for this, so one could read the clock or mutate a constant with nothing objecting.

  **The seams are inside `Shipshape/NoDistantWrites` and deliberately outside
  `Shipshape/NoAmbientReads`.** A controller mutating a constant is the same defect it is
  anywhere; a controller *reading* ambient state is the entire job of a seam, and a cop
  firing on `params` would be refusing the thing it exists to permit.

- **Guard's limit:** both hold **closed lists** — a new ambient source is uncovered until
  it is named, and the lists are the authority on what the law means in practice. Mutating
  a collaborator reached *through* a handed-in object is legal here and can still act at a
  distance; that is not caught by anything. `send`-based reads and writes are invisible. A
  gem doing any of this on your behalf is invisible.

  **Publishing to a subscriber list now has its own matcher.** Beyond the assignment shapes —
  `gvasgn`, `cvasgn`, `[]=`, `<<`, and a call ending in `=`, all only on a constant receiver —
  `NoDistantWrites` also fires on `ActiveSupport::Notifications.subscribe`/`.instrument`, and
  on any of `NoLifecycleCallbacks`'s hook names (`after_save`, `after_commit`, …) called on a
  named constant instead of written inside the record it will run against — the "attached
  from outside" case that law's Guard's limit hands off here. All of it still requires a
  **constant receiver**: a subscriber list held any other way (an instance held elsewhere, a
  class-level reader), wired through a pub/sub gem other than `ActiveSupport::Notifications`
  (wisper, dry-events, rails_event_store), or reached through `send`, passes untouched.
