# An authorisation audit — the permission set the operations are sized to

A procedure, meant to be followed by an agent one step at a time. Every step ends with
something to **run**, because a decomposition nobody can verify is a rewrite with extra
confidence.

**What you are aiming at:** a table, not a change —

| candidate permission | gates | granted to |
|---|---|---|
| `SettleInvoice` | `InvoicesController#settle` | finance, admin |
| `EditBooking` | `BookingsController#update`, `#reschedule` | agent, admin |
| — (ungated) | `ReportsController#export` | nobody found it — ask a person |

Nothing here is written back to the application. The table is read by
[the operations step](an-adoption-order.md), which builds `SettleInvoice` and `EditBooking` as
one class each because that is what this table says exists — not one class per table the
schema happens to expose.

## Why this runs before the operations, and not after

[`a-permission-is-the-class-name`](../laws/a-permission-is-the-class-name.md) sizes an
operation by "who is allowed to do it" — one actor, one permission, one class. That fact
already exists in every Rails application before shipshape arrives: as a CanCan `can`, a
Pundit policy, an `if current_user.admin?`, a `before_action`, or a role column. **Reading it
changes nothing** — no base class, no check, no `actor:` keyword argument anywhere — so it can
happen before any operation is written. Enforcing it is a different act, and stays where
[the adoption order](an-adoption-order.md) puts it: last, because a base class demanding an
actor on day one stops every call site at once.

Run this audit without it, and the LLM writing the operations has only the schema for a
signal — which is how a real migration produced hundreds of small CRUD-shaped commands, sized
by table instead of by permission, with authorisation not even looked at until three steps
later.

## Why this is a procedure, not a tool

A tool that read CanCan, Pundit and ad-hoc role checks reliably would have to parse a DSL
(`can :manage, Booking do |b| ... end`, arrays of actions, `cannot`, aliases), a naming
convention that varies by app (`BookingPolicy`, `Bookings::Policy`, a `policy_class`
override), and free-form Ruby (`if current_user.admin? || booking.owner == current_user`).
Each of those is a large, fragile build, and every application spells at least one of them
differently — the same shape [`a-concern-nobody-modelled.md`](a-concern-nobody-modelled.md)
found in co-nullity, which needed a query the schema cannot answer rather than a cop. Greps
below, read by a person, beat a parser that half-detects one framework and stays silent about
every app that does not use it.

**`shipshape report`'s `AuthorisationScatteredOnClasses` row is the one part of this that is
already a tool** — it finds ad-hoc predicates by name (`can_flag?`, `is_admin?`, `_by_user?`)
on any class outside `app/commands`, `app/queries`, `app/workflows`, `app/operations`. Start
there; the greps below cover what its name-matching cannot: CanCan's DSL, Pundit's file
layout, and the call sites rather than the definitions.

---

## 0. Read what a name-based measure already finds

```sh
bundle exec shipshape report
```

Read the row **Authorisation decided on a class**. Every finding is a public predicate whose
name reads as permission, living outside an operation.

**Check:** you have the list of file, line and method name for every finding in that row.

---

## 1. Find CanCan, if it is here

```sh
grep -rn "can :\|can?\|cannot :\|authorize!\|load_and_authorize_resource" app config
find app -iname "ability.rb"
```

An `Ability` class is a table of `subject → actions → conditions` written as method calls, not
`def`s, so step 0's measure cannot see it. Read `app/models/ability.rb` (or wherever
`find` puts it) by hand: each `can` line names the actions it grants and the role or condition
that earns them.

**Check:** every `can`/`cannot` line has the role or condition next to it in your notes, and
every `authorize!` / `load_and_authorize_resource` call site has the controller and action
next to it.

---

## 2. Find Pundit, if it is here

```sh
find app/policies -name "*.rb"
grep -rln "authorize \|policy_scope\|Pundit::Authorization\|include Pundit" app
```

A policy's public `?`-suffixed methods (`update?`, `destroy?`) are the permissions; the class
name plus Rails' default `<Model>Policy` convention (or a `policy_class` override, grep for
it) says which controller they gate.

**Check:** every policy file has its predicate methods listed against the controller actions
that call `authorize` for that model.

---

## 3. Find the ad-hoc call sites step 0 cannot see

Step 0's measure finds where a permission-shaped method is **defined**. It does not find
where it is **called** from a controller, which is the fact that gates an action:

```sh
grep -rn "current_user\.\(can_\|may_\|is_\|admin?\|owner?\)" app/controllers
grep -rn "before_action :authorize\|before_action :require_" app/controllers
```

**Check:** every hit has the controller action it sits in (or the `only:`/`except:` list of a
`before_action`) written next to it.

---

## 4. Find a role column or enum standing in for all of the above

```sh
grep -n "t\.\(integer\|string\)\s*\"\?role" db/schema.rb
grep -rn "enum role:\|enum :role" app/models
```

A role column with no `can`, no policy and no predicate is authorisation implemented entirely
in `if user.role == "..."` scattered at call sites — repeat step 3's grep with the role's
actual values (`admin`, `staff`, whatever the enum names) if the generic verbs miss it.

**Check:** either this grep is empty, or its hits are already accounted for in step 1 through
3's notes — a role column feeding a CanCan `can` block is one fact, not two.

---

## 5. Attach every gate to the actions it protects

```sh
bin/rails routes
```

For each permission found in steps 0 through 4, write down every controller action it gates —
by `only:`/`except:` on a `before_action`, by which actions in a CanCan `Ability` block the
subject's actions expand to (`:manage` is all seven), or by which actions call `authorize` for
a Pundit-covered model. Cross the list against `bin/rails routes` for the controller: an
action in the routes with no gate found is a candidate for row three of the table above.

**Check:** every route for a controller that appears anywhere in steps 0 through 4 has a
row — gated by something, or explicitly ungated.

---

## 6. Minimise — this is the judgement, and no step above makes it

**The tool gathers; you decide.** Three moves, in order:

- **Two permissions granted to the same roles, never apart, are one permission.** If
  `can_settle?` and `can_export_invoice?` are true for exactly the same set of actors on every
  row you found, they are one deed wearing two names, not two operations.
- **A permission gating exactly one action is already deed-sized.** Leave it; it is the
  `SettleInvoice` row above, and the operations step of the adoption order builds it as one
  class.
- **An action gated by more than one permission is the auth-graph inflation this canon exists
  to reduce.** Name which of the permissions is the real gate for this action and which is
  redundant — or split the action, if it is genuinely doing two things under one route.

**An action gated by nothing is not a finding for you to resolve.** It is either deliberately
public (a health check, a webhook with its own signature check) or a hole. Write it down as
"ungated" and ask a person; guessing which one it is is exactly the verdict this audit must
not produce.

**Check:** every row in your table names one permission, the actions it gates, and the roles
or conditions that earn it — and every "ungated" row is a question, not an assumption.

---

## What this leaves you

**The spec for the operations step.** [The adoption order](an-adoption-order.md) builds one
class per row in this table — sized by what the application already enforces, not by what the
schema happens to expose. Nothing has been enforced yet; `EveryDoorChecksPermission` and
`AnonymityIsClosedDownward` still report zero, same as before this audit ran, because
installing authorisation is a separate, later act.

## What none of this proves

**This audit sees code, and only some of it.** It cannot see:

- **Authorisation enforced in a view** — a link hidden by `if current_user.admin?` in a
  template, with the action itself left open to anyone who knows the URL. Steps 1 through 4
  grep `app/controllers` and `app/models`; repeat them against `app/views` if a codebase is
  known to hide rather than block.
- **Authorisation living in a gem** — a mountable engine or a third-party controller
  concern that runs its own `before_action` outside this application's source. `bin/rails
  routes` still lists the route; the grep will not find what gates it.
- **Authorisation reached through `send`, a variable, or metaprogramming** — the same limit
  [`a-permission-is-the-class-name`](../laws/a-permission-is-the-class-name.md) states for
  `CallGraph` itself: these greps are syntactic, and a dynamically dispatched check is
  invisible to all of them.
- **Whether an ungated action is deliberately public.** The audit produces the question, never
  the answer — that is the discipline this whole procedure exists to hold. An LLM handed a
  verdict stops modelling; handed a list of ungated routes, it has to ask.
