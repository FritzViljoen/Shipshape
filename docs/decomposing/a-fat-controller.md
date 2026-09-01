# Decomposing a fat controller — the action is deciding, not placing

A procedure, meant to be followed by an agent one step at a time. Every step ends with
something to **run**, because a decomposition nobody can verify is a rewrite with extra
confidence.

An action that parses, finds, checks, branches, writes, and renders. It is the largest
cluster in every report — in lobsters, five measures and about five hundred findings all
describe this one shape.

**An action places what an operation answered.** It reads the request, calls one thing, and
chooses a response. Everything else it currently does belongs somewhere with a name.

**What you are aiming at:**

```ruby
def update
  if EditStory.call(actor: actor, story_id: integer_param!(:id), title: text_param!(:title)).success?
    redirect_to story_path
  else
    render :edit, status: :unprocessable_entity
  end
end
```

Parse at the seam, call one thing, place a response per outcome. The action tests `success?`
and `present?` and nothing else — every other question moved inside the operation.

## It is a command turned inside out

**The command is already written — it is in the action, with its parts the wrong way round.**
Nothing here is designed from scratch, and that is what makes this the most mechanical
procedure in the playbook once the reading is right.

| In the action | What it is in the command |
|---|---|
| `return render :forbidden unless @story.editable_by?(current_user)` | the permission the base class checks, so it disappears |
| `return render :not_found unless @story` | `failure(:not_found)` |
| `if record.save … else …` | `success(record)` / `failure(:invalid, ...)` |
| `transaction do … end` | the whole of `call` |
| `@story = Story.find_by(...)` | a query, or the command's own load |
| each `render` / `redirect_to` arm | one outcome the result has to be able to carry |

**The last row is the load-bearing one.** An action's response arms are the command's result
vocabulary, and counting them says what the command must be able to answer with before a line
of it is written. Four arms means four outcomes; a command that can answer two of them has
left the other two being decided in the controller.

**The branch count does not fall, and that is not a failure.** The same conditions exist
afterwards — on the inside, where the domain is, rather than on the outside, where the
placement is. What falls is the number of things deciding, which is what
`Shipshape/NoDecisionsInRequestHandling` counts and what `shipshape report` ranks.

---

## 0. Make it visible

```sh
shipshape coverage
shipshape next
```

Controllers are in the default globs, so this usually already works — which is why the
findings are visible before anything else is configured, and why this is the tempting place
to start. **It is not the cheapest place**: an action's rules usually live on the record it
touches, so [a god record](a-god-record.md) often has to come first or the extracted command
is just a wrapper around the same god object.

---

## 1. Parse at the seam, and only there

```ruby
integer_param!(:id)      # not params[:id]
date_param!(:on, time_zone: time_zone_param!(:zone))
```

Do this first and mechanically. `rubocop -A --only Shipshape/NoSilentCoercion,Shipshape/NoUnparsedLookup,Shipshape/NoInlineParamParse` corrects the deterministic subset — but read the diff: it is `SafeAutoCorrect: false` because a silent `0` becomes a bounce, which is the rule and is not behaviour-preserving.

**Check:** `Shipshape/NoInlineParamParse` and `NoUnparsedLookup` are silent.

---

## 2. Name what the action is actually doing

Write the sentence: *"this action …"*. If the sentence needs an "and", it is two operations
and the response chooses between them at the edge.

`Shipshape/NoDecisionsInRequestHandling` names every branch on domain state. Each one is a
decision that belongs in the operation — and the decision's *answer* is what comes back.

**And if the action contains a `transaction do`, that block is the command** — its contents
are the new `call`, and everything before it is the action's own work. Somebody already
decided what had to be atomic; see [the index](README.md), "Start from the transaction blocks".

**Check:** you can name the command or query before writing it.

---

## 3. Move the finding, then the deciding

```ruby
# before
@story = Story.find_by(short_id: params[:id])
return render :not_found unless @story
return render :forbidden unless @story.editable_by?(current_user)
```

The find is a **query**. The permission is the operation's own business — with authorisation
installed, the base class asks it before the work runs, so the action never sees it.

`Shipshape/CallGraph` is what holds this: request handling has no edge to a record, so the
find has to move for the file to go green.

**Check:** `CallGraph` is silent on the controller — nothing reaches a record.

---

## 4. Leave exactly one branch

```ruby
def update
  result = UpdateStory.call(actor: current_user, id: integer_param!(:id), ...)

  if result.success?
    redirect_to story_path(result.value)
  else
    render :edit, status: :unprocessable_entity
  end
end
```

**`result.success?` is the only condition an action may test.** It is not a decision — the
decision was made and came back as a value; the action is placing it.

Where several responses are needed, branch on the failure *code*, not on domain state:
`result.error` is a symbol the operation chose, and adding a case is the operation's change,
not the controller's.

**Check:** `Shipshape/NoDecisionsInRequestHandling` is silent.

**And check the workflow you just extracted, if you extracted one.** The decision does not
stop being a decision by moving one level in: a workflow sequences and does not work, so it
branches on `success?`, `failure?` or the error code and never on what a step answered with.
`Shipshape/WorkflowsBranchOnOutcome` fails `charge.value.total > 100` — a rule about totals
that now applies to this one sequence instead of to every caller of the operation that owns
them. The commonest way to fail this step is to move the branch rather than the rule.

---

## 5. The instance variables are a shape

`@story`, `@comments`, `@user` set for the template are three unasserted values with no
contract. One shape, built by the query, is what the view should be handed —
`view_component` may hold shapes and nothing else.

**And the fields the shape carries are answers, not ingredients.** Wherever the action or the
component worked a value out — a total, a difference, a `full_name`, a `ends_at < now` — that
derivation moves into the query that builds the shape and arrives as a field.
`Shipshape/OnlyOperationsCalculate` names each one. Moving the arithmetic into a private
method of the component is the way this step gets failed: the rule is still outside the
operation that owns it, one call deeper.

**Check:** `Shipshape/OnlyOperationsCalculate` is silent on the controller and on the
component, and "Actions orchestrating several classes" falls in `shipshape report`.

---

## 6. Stop when the count stops falling

```sh
shipshape check
```

---

## What this leaves you

**The action is readable in one screen and says nothing about the domain.** A rule changes in
one place, and the controller is not one of the places you have to check.

## What none of this proves

Whether a `before_action` is a decision. Most are — a filter that finds, authorises, or
branches is the action's work moved one line up, and the cop does not see it because it is
not a conditional in the method. The report counts what the action does; a filter chain that
does the deciding for it is invisible to both, and that is the honest limit here.
