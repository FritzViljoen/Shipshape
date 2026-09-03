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

**Inside an operation, parsing is the same hole as reading the clock.** `Time.parse`,
`Time.strptime`, `Time.iso8601` and the `DateTime` twins take their zone from the process,
so the same string lands on a different instant on a differently configured machine —
`Time.new` with date parts and no offset does too. `.to_time`, `.to_datetime` and `Time.at`
are a different fact, not that one: the instant they name does not move, only the offset
now stamped on the result does, and a caller reading the hour or the day off it reads the
wrong wall clock for anyone elsewhere. `Date.parse` and `DateTime.new` are exempt on
purpose — a calendar date carries no zone, and `DateTime.new` defaults its own offset to
UTC rather than asking the process for one.

- **Principle:** `nothing-crosses-unasserted`. `absence-is-absence` produces the no-default
  half: an ambient zone is a fact nobody stated.
- **Guard:** the required keyword, which is the language's own error at the call site; the
  offset check in the parser; `Shipshape/TypedArguments`, which holds the declared-type half
  at lint time; `typed`'s own `matches?`, which holds the value half at runtime; and
  `Shipshape/NoAmbientReads`, which forbids the ambient read, the naive parse and the naive
  cast that would go around all four.
- **Guard's boundary:** a parse inside `request_handling` or `entry_point` is
  `input-is-parsed-at-the-seam`'s business, held by `Shipshape/NoInlineParamParse`, not this
  one — `NoAmbientReads` is not scoped to those kinds, so the two never report the same call.
  The seam's own answer is `time_param!(key, time_zone:)`, which is what `NoAmbientReads`
  names as the fix.

- **Guard's limit:** nothing stops an ambient zone being read outside the trees
  `NoAmbientReads` covers. Within its trees the read list is closed. Neither guard can tell
  whether a `Date` should have been a moment. The naive-parse and naive-cast lists are closed
  too, and check the spelling at the call site: `Time.new` with an explicit `utc_offset` as a
  7th positional argument, rather than `in:`, is not recognised as naming its own zone.

  `Shipshape/TypedArguments` only reads inside `initialize` of a governed kind: a bare
  `typed(at, Time)` in `call`, or in a private assert helper reached from `initialize`,
  reports nothing. It also matches the spelling written at the call site, not the type it
  resolves to — `Moment = Time` then `typed(at, Moment)` reports 0, and so does `MyApp::Time`.

  `install` never overwrites, so an application installed before this fix keeps the old,
  permissive `matches?` — the value half is simply absent there.
