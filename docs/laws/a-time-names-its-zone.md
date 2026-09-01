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

- **Principle:** `nothing-crosses-unasserted`. `absence-is-absence` produces the no-default
  half: an ambient zone is a fact nobody stated.
- **Guard:** the required keyword at the seam, which is the language's own error at the call
  site, and the offset check in the generated parser.
- **Guard:** `Shipshape/TypedArguments`, over every operation kind. Refuses a keyword declared
  as a bare `Time` or `DateTime`, and names `ActiveSupport::TimeWithZone` for a moment or `Date`
  for a calendar date instead. **The declared type is the only place this is visible.** At
  runtime `ActiveSupport::TimeWithZone` answers `is_a?(Time)` with true, so an assertion against
  `Time` admits a naive value and the argument guard cannot tell the two apart — a static read
  of what the author wrote can.
- **Guard:** `Shipshape/NoAmbientReads`, over the operation, value and legacy-door trees.
  Refuses the clock and the ambient zone, and with them the builders and casts that take a zone
  from the process without naming it: `Time.parse`, `Time.strptime`, `Time.iso8601`, `Time.at`,
  `Time.new`, the `DateTime` twins of the first three, and a bare `.to_time` or `.to_datetime`.
  `Time.zone.parse(raw)` is refused as the ambient-zone read it is.

- **Guard's limit:** the type refusal reads the **declared** type and nothing else. It holds a
  keyword the author declared `Time` or `DateTime`; it says nothing about the value that
  arrives, and nothing about a keyword declared with some other class that a naive value would
  also satisfy. It hangs off `def initialize`, so an operation with no initializer is invisible
  to it, and it cannot see a guard reached through a helper it does not know by name.

  `Shipshape/NoAmbientReads` holds **closed lists** — a builder, cast or clock the lists do not
  name is uncovered — and holds them only inside the trees it governs, so nothing stops an
  ambient zone being read outside those trees. `Date.parse`, `Date.new` and `.to_date` are
  deliberately absent: a calendar date carries no zone, so building one reads nothing ambient.

  **Neither guard can tell whether a `Date` should have been a moment**, or whether a String
  is the wall-clock reading this law permits rather than a moment somebody flattened. And a
  zoned value is not a correct one: nothing checks that the zone named is the right zone for
  the fact.
