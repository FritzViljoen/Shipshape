# Decomposing a filter chain — the action's work, moved one line up

A procedure, meant to be followed by an agent one step at a time. Every step ends with
something to **run**, because a decomposition nobody can verify is a rewrite with extra
confidence.

**What you are aiming at:**

```ruby
# before — two places decide, and they can disagree
before_action :require_editable, only: %i[edit update]

# after — one place decides, and the action places what came back
def update
  if UpdateStory.call(actor: current_user, id: integer_param!(:id), title: title).success?
    redirect_to story_path
  else
    render :edit, status: :unprocessable_entity
  end
end
```

The rule moves inside the operation that needs it, and comes back as an outcome. The filter
chain stops being a second, invisible place where the same question is answered differently.

The shape: a controller with six `before_action`s and actions three lines long. It looks like
the fat controller was already decomposed. It was not — the work moved above the actions,
where nothing reads it.

**This is the stated limit of [a fat controller](a-fat-controller.md)**, and it is why this
procedure exists. `Shipshape/NoDecisionsInRequestHandling` finds branches *in a method*. A
filter is a different method, and the branching is in `only:`, `except:` and `if:` — a control
flow written in macro arguments, which no cop here reads and no reader can follow without
holding six declarations and an inheritance chain in their head at once.

---

## 0. List them, including the ones this file does not contain

```sh
grep -rn "before_action\|prepend_before_action\|around_action\|after_action\|skip_before_action" app/controllers
```

**The inherited ones are the point.** A filter declared in `ApplicationController` runs for
every action in the application, and the file you are reading does not mention it. Start from
the base class and work down, so the list for one controller is the base's filters plus its
own, minus its `skip_before_action`s.

**`skip_before_action` is the `unscoped` of controllers** — an escape hatch that exists because
the rule was applied to everything, and its presence says the rule was wrong somewhere.

**Check:** for one action, you can write the ordered list of everything that runs before it,
and say which file each entry came from. If that takes more than a minute, that is the finding.

---

## 1. Sort each filter into one of four kinds

| Kind | Example | Where it ends up |
|---|---|---|
| **Authenticate** | `require_login` | stays — it produces the actor, which every operation takes |
| **Find** | `@story = Story.find(params[:id])` | into a read, or into the operation, which takes the id |
| **Authorise** | `redirect_to root unless @story.editable_by?(current_user)` | disappears — the operation's base class checks |
| **Decide** | `redirect_to onboarding_path unless current_user.onboarded?` | into a write; comes back as a failure code |

**Only the first survives.** Authentication is the seam's job: identify the caller, hand the
actor onward. Everything else is the action's work, and the action's work belongs in an
operation — which is what [a fat controller](a-fat-controller.md) says, one line lower down.

**Check:** every filter in your list has one of the four labels, and you can say why.

---

## 2. Take the authorisation out first, because it deletes rather than moves

An authorisation filter has no destination. With the base class checking every operation, the
filter is not moved anywhere — it stops existing, and the operation refuses on its own.

```ruby
# before: two places decide, and they can disagree
before_action :require_editable, only: %i[edit update]

# after: one place decides, and the action places what came back
def update
  result = UpdateStory.call(actor: current_user, id: integer_param!(:id), ...)
  ...
end
```

**This is where the count falls fastest**, and it is safe: deleting a check that another check
already makes cannot open a hole. Deleting one that nothing else makes can, so confirm the
operation exists and checks before deleting the filter, not after.

**Check:** `Shipshape/EveryDoorChecksPermission` is silent, and the operation's own test
refuses an actor who may not run it.

---

## 3. Move the find into the thing that needed it

`@story = Story.find(params[:id])` in a filter is a record assigned to an instance variable
that four actions then read. The operation should take the id.

`Shipshape/CallGraph` is what holds this: request handling has no edge to a record, so the
find has to move for the file to go green. `NoUnparsedLookup` refuses the raw param on the way.

**The `@story` that survives is a smell of its own** — several actions reading one ivar set
somewhere else is [a fat controller](a-fat-controller.md)'s step 5, and the answer there is a
shape built by a read.

**Check:** `CallGraph` and `NoUnparsedLookup` are silent on the controller.

---

## 4. The deciding filter is a write, and the redirect is its failure code

```ruby
# before — a rule about onboarding, enforced from a controller filter
before_action :require_onboarded

# after — the rule is the operation's, and the action places what came back
def create
  result = PostComment.call(actor: current_user, ...)
  return redirect_to onboarding_path if result.error == :not_onboarded

  ...
end
```

**Moving it up into a filter and moving it into a write are not the same move**, and the
filter version is the one that scales badly: the rule is now enforced for the actions somebody
remembered to list, and the list is in a macro argument. Adding an action is how the rule stops
applying, silently.

**Check:** `Shipshape/NoDecisionsInRequestHandling` is silent, and the rule has one home you
can grep for by name.

---

## 5. Read what `only:` and `except:` were really saying

A filter with `only: %i[edit update destroy]` is one name covering three different obligations
that happened to coincide. When they stop coinciding, somebody adds a fourth action and either
over-applies the rule or forgets it.

**One filter, one meaning.** If the list is doing work, the filter is several rules sharing a
name — which is the same defect [one way to say each thing](../principles.md) names everywhere
else, wearing a macro.

**Check:** no surviving filter carries an `only:` or `except:` longer than one action, or you
can say why the actions genuinely share one obligation.

---

## 6. Stop when the chain is one line

```sh
shipshape check
```

The end state is authentication and nothing else. Not zero — an application has to know who is
calling — but one, declared once, in the base controller, with no `skip`.

---

## What this leaves you

**An action you can read top to bottom without leaving the file.** What runs before it is one
thing, it is the same one thing for every action, and the rules that used to be above the
actions are in operations with names.

## What none of this proves

**A filter that renders or redirects halts the chain, and moving it changes what runs after
it.** This is the failure mode of this procedure and it is not theoretical: `require_login`
redirecting means `require_onboarded` never ran, and the code after it assumed as much. Pull
the redirect out and the later filter now runs against a `nil` current user.

Work down the list in order, one filter at a time, and keep the edge tests from
[characterise the edges](characterise-the-edges.md) green after each — they are the only thing
that sees a chain that stopped halting.

**And `around_action` is worse than either**, because the halt is a block that may or may not
`yield`. Nothing in this procedure reads that; treat one as unknown until you have read it.
