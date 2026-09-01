# A form that fails — the cost this canon does not otherwise state

A procedure, meant to be followed by an agent one step at a time. Every step ends with
something to **run**, because a decomposition nobody can verify is a rewrite with extra
confidence.

**What you are aiming at:**

```ruby
# the command answers the same shape the form was built from, so the page can redraw itself
result = SendMessage.call(actor: current_user, to: recipient, body: body)
return redirect_to messages_path if result.success?

@form = result.value          # a failure carries what was wrong
render :index
```

The request was parsed at the seam and is gone, so a refusal has to bring back something the
edge can place. That is why a failure carries a value: not for the caller to inspect, but for
the page to render.

**This one exists because a real refactor hit a wall three times and every wall had the same
cause.** Extracting `MessagesController#create` in lobsters ran into: a failure that could not
carry the invalid record, a `Query` that must answer shapes, and a view calling `form_with
model: new_message`. One cause, stated plainly:

> **Adopting this canon means the view layer stops holding ActiveRecord objects.** Rails' view
> layer is built on the assumption that it does. That is the largest cost of adoption and no
> other procedure here mentions it.

If that is not acceptable for a given application, the honest answer is to leave its views
alone and stop the boundary at the controller — not to pretend the cops are wrong.

---

## 0. Know which wall you are at

```sh
shipshape next --json
```

Three symptoms, one cause:

| What you see | What it means |
|---|---|
| `failure(:invalid)` and nothing to render | a `Result` is a `Shape`, and a shape refuses to hold a record |
| `Query#call must answer with shapes` | the list the template iterates cannot be records |
| `CallGraph`: request handling may not reach a record | `@story = Story.find(...)` for the view |

**Check:** you can say which of the three you are at, and that you know they are the same
thing.

---

## 1. The happy path first, and stop there if you like

The success path almost never needs the record: it redirects, or it renders something a query
already shaped. Extract that, leave the failure path as it was, and the count falls.

```ruby
result = SendMessage.call(author_id: @user.id, subject: subject, body: body)
return redirect_to messages_path if result.success?

# unchanged, for now
@new_message = Message.new(message_params).tap(&:valid?)
render :index
```

**This is a legitimate stopping point.** The ratchet exists so a half-finished state is legal,
and most of the value — the decision moved out of the action — is already banked. What is left
is a view migration, and it is a bigger job than the extraction was.

**Check:** `shipshape check` — the count fell. The action has one branch, `result.success?`.

---

## 2. When you do continue: the failure carries a shape

`Result.failure` takes a value, and that value obeys the rule everything a shape holds obeys —
**it may not be a record**. So what comes back is the fields and the messages:

```ruby
class Draft < Shape
  def initialize(subject:, body:, errors:)
    @subject = typed(subject, String)
    @body    = typed(body, String)
    @errors  = typed_hash(errors, Symbol, Array)
  end

  attr_reader :subject, :body, :errors      # a shape is read; that is its job
end

return failure(:invalid, Draft.new(subject: @subject, body: @body,
                                   errors: message.errors.to_hash)) unless message.save
```

**Check:** the command's tests assert on `result.value.errors`, and `Result.failure` does not
raise — which it does if you try to hand it the record.

**No `ActiveModel` anywhere.** An earlier draft of this procedure reached for
`include ActiveModel::Model` to keep `form_with model:` working, and that was the wrong trade:
it puts the framework inside a shape to preserve the one idiom this whole step exists to
remove. The next section replaces the idiom instead.

---

## 3. The form is fed by a query, like everything else on the page

`form_with model:` is the line to stop writing. It takes the **route**, the **field names** and
the **errors** from a record, which is three reasons the view needs one — and it is the only
reason left once the rest of the action has moved.

Replace it with the two things it was deriving, stated:

```erb
<%= form_with url: messages_path, scope: :message do |f| %>
  <%= errors_for form.errors %>

  <%= f.label :subject %>
  <%= f.text_field :subject, value: form.subject %>

  <%= f.label :body %>
  <%= f.text_area :body, value: form.body %>
<% end %>
```

**`scope:` is the load-bearing half.** It produces `message[subject]` exactly as `model:` did,
so the submitted parameters are byte-identical, the route is unchanged, and the controller and
`message_params` do not move. The migration is confined to the template.

And `form` is what a query answered:

```ruby
class NewMessageForm < Query
  def call
    MessageForm.new(recipient_username: "", subject: "", body: "", errors: {})
  end
end
```

**A form is a read.** It was never anything else — the page is showing you fields — so it comes
from a query returning a shape, like every other read on the page. The record was only ever
standing in for a view model nobody had written.

**A list on the same page is the same rule**, and a query answers an array of shapes for it:

```ruby
class Inbox < Query
  def call
    MessageRecord.inbox(@reader_id).map { |row| MessageSummary.new(subject: row.subject, ...) }
  end
end
```

**The failure path now converges with the new-form path**, which is the part worth having.
Before, `new` built a record and `create`'s failure branch built another one and re-validated
it; two constructions of the same page, and only one of them was ever exercised by a test. Now
both render one shape — the query supplies it empty, the failed command supplies it filled:

```ruby
result = SendMessage.call(...)
return redirect_to messages_path if result.success?

@form = result.value           # the same shape NewMessageForm answers
render :index
```

**Check:** the rendered HTML has the same `name="message[...]"` attributes it had before.
That is the property the whole step turns on, and it is checkable by diffing the page.

## 4. The lists the template iterates

`Query#call` refuses anything that is not a shape, so `@messages = Message.inbox(user)` cannot
be extracted until the template stops calling record methods on each row.

Do this **per template, not per query.** A query returning shapes whose template still expects
records fails at render, in the browser, at whatever moment somebody looks — and the failure is
a `NoMethodError` on a shape, which reads like a bug in the shape rather than a migration
half-done.

**Check:** the template names only methods the shape defines. Grep it for the ones it calls.

---

## What this leaves you

**A page that can redraw itself from what the refusal carried.** The request was parsed at the
seam and is gone, so a failure that carried only a code would leave the edge with nothing to
render. Now the same shape the form was built from comes back, and the action places it.

## What none of this proves

**Nothing here shows the page still renders**, and the checks are especially weak in this
procedure: every cop is silent on a template. A shape missing a method the view calls is green
in every check shipshape has and broken on the page.

So the verification for this one is not a cop. It is opening the page — the success path and
the failure path, with a deliberately invalid submission — and looking at it. A system test
that posts invalid params and asserts the error text appears is the version of that which
survives, and it is worth writing **before** step 2, because it is the only thing that will
tell you the migration landed.
