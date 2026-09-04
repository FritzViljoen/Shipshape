# `input-is-parsed-at-the-seam` — Request input is parsed once, at the edge, by named parsers

A parameter is a string somebody typed. It becomes an Integer, a Date, a time, a decimal, a
boolean, a bounded string, or a value from a closed set — in one place, at the edge, and
once.

**Never inline in an action**, where a parse turns a typo into a 500. **Never in the
domain**, which is handed real values and asserts them
([`arguments-are-typed-at-construction`](arguments-are-typed-at-construction.md)).

**Each parser has two forms.** The plain one answers with the caller's default; the bang
form bounces. A value past a declared limit bounces from **both** — a silent fall back to
"no filter" answers an over-long search with everything, which is the broadest possible
answer to a question nobody asked.

**And a raw parameter never reaches a record.** `find(params[:id])` works, which is the
trap: the adapter coerces the string, so `/people/1abc` serves record 1 and nothing
anywhere fails. The parsers refuse it, but a seam cannot defend a door nobody opened.

**Absence is nil or empty, and deliberately not `blank?`.** `false.blank?` is true, so a
blank guard turns a parameter that says *no* into the default — the request states a fact
and the application hears nothing. Absence and a value of false are different things, and
only one of them is absence.

- **Principle:** `nothing-crosses-unasserted`, and `nothing-fails-quietly` for the bouncing
  half. On conflict `nothing-crosses-unasserted` governs.
- **Implementation:** `shipshape install` writes `TypedParams` into the application, beside
  the base classes. The law needed something to parse *with*, and a law whose only
  implementation is private is a law nobody can keep.
- **Guard:** the generated `typed_params.rb` — architecture. The parsers raise on input
  they cannot read, so a seam has no way to coerce silently.
- **Guard:** `Shipshape/NoInlineParamParse` flags `parse`, `strptime`, `iso8601` and their
  siblings on a closed list of receivers — `Date`, `Time`, `DateTime`, `BigDecimal`,
  `ActiveSupport::TimeZone` — and the bare raising conversions (`Integer(...)`, `Float(...)`),
  whenever the value came from request parameters.
  `Shipshape/NoUnparsedLookup` flags a request value reaching a finder or a writer — as an
  argument, in a hash, or nested any depth down.

- **Guard's limit:** both hold **closed method lists**, so a finder or a parser they do not
  name is uncovered. The parameter must be reached syntactically inside the call, so a local
  assigned from it earlier is invisible. `to_i` and `to_f` cannot raise, so they are left to
  [`no-silent-coercion`](no-silent-coercion.md). Views are not covered.
