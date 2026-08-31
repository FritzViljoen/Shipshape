# Decomposing a cadence in code — work that starts under nobody's name

A procedure, meant to be followed by an agent one step at a time. Every step ends with
something to **run**, because a decomposition nobody can verify is a rewrite with extra
confidence.

The shape: `config/schedule.rb`, a `sidekiq-cron` initialiser, a `Clockwork` file. Fourteen
entries. Nobody can say what they all do, whose authority they run under, or which of them
still matter.

**A schedule is a controller action called at a set frequency** — something outside arrives, an
actor is established, one command runs. The caller being a clock rather than a browser earns no
second mechanism, so the schedule is a **row**: a stored request, with the actor a `NOT NULL`
column. [`a-schedule-is-a-row`](../laws/a-schedule-is-a-row.md) is the law, and
`Shipshape/NothingSchedulesWork` fails the code version.

---

## 0. Inventory what runs, and under whose name

```sh
shipshape check --only Shipshape/NothingSchedulesWork
grep -rn "every \|Sidekiq::Cron\|Clockwork\|recurring " config lib
```

Then the ones that are not in the repository at all, which is the half nobody has a list of:

```sh
crontab -l                              # on each host
kubectl get cronjobs --all-namespaces   # if it is there
```

**The out-of-repository ones are the worst and the cop cannot see them.** A `rails runner`
line in `/etc/cron.d` has no actor, no audit entry and no permission check — it steps around
every door at once, and it is invisible to everything in this canon.

**Check:** one list, with a source for each entry, including the hosts.

---

## 1. For each entry, answer "as whom?"

This is the question the shape exists to force, and most entries have never been asked it.

| Answer | What to do |
|---|---|
| a named person or role — the treasurer, the ops lead | that is the row's `actor_id` |
| "the system" | **stop.** Somebody is accountable for this running, or it should not run |
| nobody knows | it is a candidate for deletion — see step 2 |

**A `SystemActor` holding every permission is not an answer**, it is an unauthenticated door
with a friendly name. The property worth having is the opposite: **revoke the person and their
schedules stop.**

**Check:** every entry has a person or role, or is on the deletion list.

---

## 2. Delete before you migrate

A schedule file accumulates. Ask git how old each entry is, the way
[a feature flag](a-feature-flag.md) does:

```sh
git log --reverse --format='%as %s' -S "settle_overdue" -- config | head -1
```

Then ask the audit log what actually ran, and what it did. An entry that has produced nothing
but no-ops for a year is a candidate; one nobody can name an owner for is a stronger one.

**Check:** the list is shorter than it was, and each deletion was a decision somebody made.

---

## 3. Point each surviving entry at a route

The row names a **route**, not a command class.

```ruby
# before — config/schedule.rb
every 1.day, at: "3:00 am" do
  runner "SettleOverdueInvoices.call"
end

# after — a row, created by a command like any other
Scheduling::CreateSchedule.call(
  actor:      actor,
  method:     "POST",
  path:       "/invoices/settle",
  params:     { tenant_id: tenant.id },
  cadence:    "0 3 * * *",
  runs_as_id: treasurer.id,
)
```

**A path is a name already promised to the outside; a class name is one refactoring is free to
change.** Storing the class name would make a rename a data migration, which is the defect
[a polymorphic association](a-polymorphic-association.md) describes arriving through a
different door.

**And the route may not exist yet.** A `rails runner` entry calling into the domain directly
has no endpoint, and giving it one is the work: the same parsing, the same permission, the same
audit entry every other caller gets.

**Check:** the path in the row resolves in `rails routes`, and calling it by hand as that actor
does what the cron entry did.

---

## 4. Let the controller defer, so a schedule is not a long request

Nightly work that takes twenty minutes is not a twenty-minute request. The controller enqueues
with `call_later` exactly as it would for a browser
([`deferral-is-one-command`](../laws/deferral-is-one-command.md)), so the chain is
schedule → request → controller → command and every hop already exists.

**Check:** the scheduled request returns in the time an ordinary request takes.

---

## 5. Two firings are a double-post, so prove the command survives it

Two servers reaching one row in the same minute is the same event as two browsers reaching one
form, and [`a-command-runs-twice`](../laws/a-command-runs-twice.md) already obliges every
command to survive it.

```sh
bundle exec rubocop --only Shipshape/CommandsProveIdempotence
```

**A lock is an optimisation here, not a correctness requirement** — which is exactly the
difference from the file you are deleting, where nothing ever obliged the work to be repeatable.

**Check:** the command's test runs it twice and asserts the second run's effect.

---

## 6. Delete the file

```sh
shipshape check
```

The cop is silent when the last cadence has left the code.

---

## What this leaves you

**A list you can query.** What runs automatically, on what cadence, as whom, and what it did
last night — four questions that had no answer while the schedule was a file, and that are a
`SELECT` once it is a row. Adding a schedule stops being a deploy.

## What none of this proves

**The host crontabs are still there.** This procedure removes the schedules the repository can
see, and the guard only ever covered those. A `rails runner` in `/etc/cron.d` survives every
step here, keeps its lack of an actor, and is now the only scheduling mechanism left — which
makes it easier to find and no less dangerous.

**And nothing fires the rows.** The runner that reads the table and makes the requests is
application code this canon does not supply, and it is the piece where the interesting failures
live: a missed window, a clock skew, a row whose route was removed. The law says what a
schedule is; it does not run one.
