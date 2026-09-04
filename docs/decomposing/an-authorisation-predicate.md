# Decomposing an authorisation predicate — auth and settings wearing one name

A procedure, meant to be followed by an agent one step at a time. Every step ends with
something to **run**, because a decomposition nobody can verify is a rewrite with extra
confidence.

The shape, and the reason it is hard:

```ruby
class Story < ApplicationRecord
  def can_be_seen_by_user?(user)  # who is asking      — a permission
  def can_have_images?            # which plan they buy — a setting
```

**Two different things, indistinguishable at the call site.** One asks whether this actor is
allowed; the other asks what this tier of account includes. They are written the same way, sit
on the same class, and read the same in a controller — and they belong in opposite places. A
permission belongs to the operation that does the thing; a setting is a row, per
[`no-industry-terms-in-code`](../laws/no-industry-terms-in-code.md).

Neither is a method on a table, which is why they are found together and sorted before
anything moves. **The sorting is the work, and no tool does it for you.**

Scattered like this, the authorisation half is also unenumerable: `story.is_editable_by_user?`,
`user.can_flag?`, `tag.can_be_applied_by?` — no screen can offer them, no grant can revoke
them, and a refusal leaves no trace.

**What you are aiming at:**

```ruby
# the permission is the class name of the deed that does the thing
EditStory.call(actor: actor, story_id: id, title: title)

# the setting is a row, read by the question that builds the shape
plan.allows_images?
```

One list answers who may do what, and it is the list a permissions screen is built from.
Nothing is left on a table deciding on the actor's behalf.

---

## Why they land on classes

Because the class is in front of you. You are writing `StoriesController#edit`, you have a
`@story`, you need to know whether this user may edit it, and `@story.is_editable_by_user?`
is the shortest thing to type. Every one of these was a reasonable decision on the day.

**What they add up to is an authorisation model that cannot be read.** Ask "what may a
moderator do here" and the answer is a grep across `app/models`, and the grep is wrong,
because two of the predicates check a column, one checks a constant, and one calls another
predicate that checks the first.

---

## 0. Inventory them, with the class they landed on

```sh
shipshape report
```

The row is **Authorisation decided on a class**. Every finding is a public predicate whose
name reads as permission, outside an operation.

Widen it by hand where your vocabulary differs — a codebase saying `visible_to?` or
`editable_for?` will not be in the default list, and a name not on the list is unexamined
rather than cleared:

```sh
grep -rn "def .*\(visible_to\|editable_for\|permitted_for\)?" app lib
```

---

## 1. Sort each one: permission, or setting?

**The test is what changes the answer.** If the answer changes when you swap the actor, it is
a permission. If it changes when you swap the account, the plan or the tenant, it is a
setting. If it changes with both, it is two things wearing one name and it splits here.

| the predicate | changes with | it is |
|---|---|---|
| `can_flag?(obj)` | who is asking | a permission |
| `can_have_images?` | which plan the account is on | a setting |
| `is_editable_by_user?(user)` | who is asking, and how old the story is | a permission and a rule |

Write the answer next to each finding before you move anything. This is the step that cannot
be automated, and it is the step that makes the rest mechanical.

**Check:** every finding from step 0 carries one of the three words — permission, setting, or
both — and none is left blank. A blank is not a small omission: it is the judgement the rest of
the procedure is waiting on.

---

## 2. A permission becomes the operation that does the thing

This is the cheap half, because
[`a-permission-is-the-class-name`](../laws/a-permission-is-the-class-name.md) means the
permission already exists the moment the deed does:

```ruby
# before — the question and the doing are in two places, and only one is guarded
if @story.is_editable_by_user?(@user)
  @story.update!(title: params[:title])
end

# after — the door asks, and `:EditStory` is a permission a screen can offer
EditStory.call(actor: actor, story_id: integer_param!(:id), title: text_param!(:title))
```

The predicate is then unreferenced. Delete it — do not leave it as a convenience, or you
have two answers to one question and the one in the model is the one that goes stale.

```sh
grep -rn "is_editable_by_user?" app lib spec test
bundle exec rspec   # or: bin/rails test
```

---

## 3. A setting becomes a row

```ruby
# before
def can_have_images?
  plan == "premium" || plan == "enterprise"
end

# after — the answer is data, and it changes without a deploy
plan.allows_images?   # a column on plans, read by the question that builds the shape
```

The shape the view holds then carries `images_allowed:` as a field, and nothing downstream
asks a question at all.

```sh
shipshape report   # the row falls by one
```

---

## 4. A rule that is neither goes to the operation, not the record

`is_editable_by_user?` that also checks `created_at > 1.hour.ago` is a permission **and** a
rule about time. The permission goes to the door; the rule goes inside `EditStory#call` and
comes back as a `failure(:too_old)`, which the action places:

```ruby
if EditStory.call(actor: actor, story_id: id, title: title).success?
```

**Check:** the rule has one home. `grep -rn "created_at > " app/models` no longer finds it, and
the deed's own test names the outcome:

```sh
grep -rn "too_old" app/deeds spec test
```

---

## 5. Run the ratchet

```sh
shipshape check
```

`Shipshape/PersistenceHoldsNoBehaviour` falls with every predicate deleted from a record, and
the report's own row falls beside it.

---

## What this leaves you

**One place that answers who may do what.** `CallGraph.grantable` lists every permission an
actor can be asked for, which is the list a permissions screen is built from and the list an
auditor asks for. Before this work that list does not exist, and cannot be written, because
the answers are scattered across classes with no common shape.

## What none of this proves

**Nothing here tells a permission from a setting.** Step 1 is a judgement, and the measure
that finds these deliberately does not make it — a tool that guessed would be wrong about the
interesting half and confident about it.

**And a predicate nobody calls is invisible to the sorting.** Step 2 tells you to grep before
deleting; a predicate reached through `send`, a serializer, or a view template will not be in
that grep, and deleting it is how a page starts raising `NoMethodError` in production rather
than in the suite.
