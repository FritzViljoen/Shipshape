# `only-an-operation-calculates` — A command and a query work a value out; nothing else does

That is the whole permission, and it is stated from that end on purpose. The rule is not
"don't calculate in views" — it is that a calculation lives in an operation, so the only
question a reader asks at any other line is whether the file they are in is one.

**A derivation is a rule, and the test is not difficulty.** `first + " " + last` is trivial
and still a rule, because it could be *wrong*: somebody has decided that a full name is those
two fields in that order with that separator, and there is exactly one place entitled to
decide it. A total, a difference, a balance and a duration are the same shape with more
arithmetic attached.

**A threshold is a rule wearing a comparison.** `ends_at < now` is the definition of "past".
Written where the row is rendered, "past" is decided by the template; written in the query, it
comes back as a field and every reader gets the same answer. Equality is not a threshold —
`row.id == selected_id` is identity, which is placement, and refusing it would refuse the
commonest correct line in a component.

**A total computed at render time is recomputed at every render**, cannot be tested without
the template, and will be worked out a second time by the next screen that shows the same
figure. That is how two totals of one thing come to disagree while both are "correct".

## The line is translating and placing

**Translate** means render a value a reader can read: `strftime`, `Money#format`, `t`, `l`, a
zone conversion. **Place** means decide where it goes: which partial, what order, what
grouping. Both belong in presentation and neither produces a new value.

Anything that turns inputs into a value that was not handed in is a rule and moves upstream —
into the command or the query. **Not into the shape**: a shape holds what it was given and
validates it, and it carries the answer the operation worked out. A shape that derives is a
second place the rule lives, reachable from everywhere a shape is.

```ruby
# a rule, in the query that owns it
class ListInvoiceLines < Query
  def call
    lines.map { |line| Line.new(total: line.units * line.rate) }
  end
end

# translation, in the component that renders it
def total
  @line.total.format
end
```

- **Principle:** `good-boundaries-make-good-neighbours` governs — a derivation written where
  it is rendered is a rule outside its one home, and the copy nobody greps for is the one that
  goes stale. `tell-dont-ask` also produces it: pulling two fields out and working the answer
  out yourself is asking, and the object that owns the answer should have been told to give it.
- **Guard:** `Shipshape/OnlyOperationsCalculate`, over `view_component`, `request_handling`,
  `entry_point` and `shape`. Fails arithmetic (`+ - * / %`) and an ordering comparison
  (`< > <= >=`) where **both** operands are reads, and `sum`, `inject` or `reduce` on any
  receiver. A literal on either side makes it an offset the author wrote down (`index + 1`,
  `count > 0`, `shown_at - 30.days`), and `+` over a collection call assembles a list rather
  than answering anything, so both pass.
- **Guard's limit:** it reads one expression, so a derivation spread over three statements, or
  moved into a private method of the same component, is invisible — the arithmetic is still
  refused wherever it finally appears, but nothing objects to the shape. **String
  interpolation is deliberately not flagged**: `"#{button_class} #{extra}"` composing CSS is
  placement and `"#{first} #{last}"` building a name is a rule, and no AST test separates
  them, so that one is review's. A `record` is out of scope because
  `Shipshape/PersistenceHoldsNoBehaviour` already refuses every method on one; the frozen
  presentation trees of a migrating application — helpers, decorators, presenters — resolve to
  no kind at all, so nothing here reaches them. Templates are not Ruby files and are not
  inspected: the same arithmetic in a `.erb` or `.slim` passes.
