# `a-time-names-its-zone` — A point in time carries its zone; a calendar date does not

Two halves of one rule.

**At the seam**, the date and time parsers take the zone as a **required** keyword. There is
no default: not a process setting, not a configured zone, and nothing read off the request
on the parser's own initiative. Where the requester's own zone is wanted, the action asks
for it — and a request arriving without one bounces because that action asked, not because
every request must carry one.

**A string that states its own offset must agree with that zone.** Where they disagree the
request holds two answers, and neither is taken: it bounces.

**In an operation**, a moment is a zone-carrying type, asserted like any other argument. A
bare `Time` or `DateTime` carries whatever offset the process had, chosen by nobody, so it
is refused **as a declared type and as a value**.

**A calendar date carries no zone, deliberately** — a departure date, an invoice date.
Converting one moves it a day. And a wall-clock reading that is not a moment — "18:30",
meaning half past six wherever it happens — travels as a String, because building a time for
one invents a date and an offset it never had.

- **Agreed:** grandfathered — predates this record, and its provenance is the repository's early history rather than a decision anybody can now point at.
- **Principle:** `nothing-crosses-unasserted`. `absence-is-absence` produces the no-default
  half: an ambient zone is a fact nobody stated.
- **Guard:** the required keyword, which is the language's own error at the call site; the
  offset check in the parser; the type refusal in the argument guard; and
  `Shipshape/NoAmbientReads`, which forbids the ambient read that would go around all three.

- **Guard's limit:** nothing stops an ambient zone being read outside the trees
  `NoAmbientReads` covers. Within its trees the read list is closed. Neither guard can tell
  whether a `Date` should have been a moment.
