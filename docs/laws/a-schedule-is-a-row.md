# `a-schedule-is-a-row` — Work that starts on a clock is a stored request, and it names its actor

**A schedule is exactly a controller action called at a set frequency.** Something outside
arrives, an actor is established, one command runs. The only difference from a request is that
the caller is a clock rather than a browser, and nothing about that difference earns a second
mechanism.

So the schedule is a **row**, and the row is a stored request: where to call, with what, how
often, and — required — as whom.

```
schedules
  method     NOT NULL   -- POST
  path       NOT NULL   -- /invoices/settle
  params     NOT NULL   -- what to send
  cadence    NOT NULL   -- how often
  actor_id   NOT NULL   -- who it runs as
```

## It names a route, because a route is a public name

**A path is a contract already promised not to break. A class name is one that refactoring is
supposed to be free to change.** Storing a command's class name in a column would make renaming
it a data migration — the defect [a polymorphic association](../decomposing/a-polymorphic-association.md)
names, arriving through a different door. A route is the name the outside already uses, so
storing it costs nothing that was not already owed.

**And it needs no new machinery.** Authentication, parsing at the seam, the permission check
and the audit entry all happen because the call went through the door every other call goes
through. There is no scheduled path into the domain, so there is no second path to guard:
`Shipshape/NoEntryPointBypass` holds the line unchanged.

The params are params. They are parsed by the same parsers
([`input-is-parsed-at-the-seam`](input-is-parsed-at-the-seam.md)), which is why the column is
not the undeclared schema that a blob of constructor arguments would be.

**Long work does not make a long request.** The controller defers with `call_later` exactly as
it would for a browser, so the chain is schedule → request → controller → command, and every
hop is one that already exists and is already governed.

## The actor is a column, so there is no system account

`actor_id` is `NOT NULL`, which by [`no-nullable-columns`](no-nullable-columns.md) means an
unattributed schedule cannot be stored. If nobody will own it, it does not get created.

**This is the whole answer to "who is the actor for scheduled work", and it needs no new idea.**
A `SystemActor` holding every permission would make `EveryDoorChecksPermission` true and
meaningless — an unauthenticated door with a friendly name. A real actor gives the property
that matters instead: **revoke the person and their schedules stop.** Someone leaves the
company and the work they set running stops running, at the door, by the mechanism that was
already there.

The audit log then names them. "Why did this run at 3am" answers with a person who could have
stopped it, rather than with the word `system`.

## Nothing new checks the permission

The controller checks at fire time, exactly as it does for a request, because it *is* a
request. There is no scheduled path around the door, because there is no scheduled path at
all — the row names a route, and the route is called the way routes are called.

## Two servers firing one row is a double-post

[`a-command-runs-twice`](a-command-runs-twice.md) already obliges every command to survive a
second call, and two servers reaching one schedule in the same minute is the same event as two
browsers reaching one form. **A lock is an optimisation here, not a correctness requirement**,
which is the difference between this and a `config/schedule.rb` where the command was never
obliged to be idempotent in the first place.

## Why a row rather than a file

A `config/schedule.rb` is code that answers no question at runtime. Nothing can ask it what
runs automatically, nothing can ask whose authority a job runs under, and nothing can grant,
revoke or audit an entry. A row answers all four by being data, and adding a schedule stops
being a deploy.

- **Agreed:** "make schedule a row and the actor is just a required field
  on it. Its exactly like calling the controller at a set frequency", after the drafted
  alternative was deleted for having been written without a decision behind it.
- **Principle:** `nothing-is-hidden` governs — work that starts by itself, under nobody's
  name, is the least visible thing a system does. `absence-is-absence` supplies the required
  actor, and `good-boundaries-make-good-neighbours` keeps the clock outside, where every other
  caller is.
- **Guard:** `Shipshape/NothingSchedulesWork`, over every governed tree. Fails a cadence
  declared in code — a `whenever` block, a `sidekiq-cron` or `sidekiq-scheduler` entry, a
  `recurring` declaration, a cron expression in a constant — because each is a schedule that
  no row records, no actor owns, and no door was opened for.
- **Guard's limit:** **it reads the application, and a crontab is not in the application.** A
  schedule in `/etc/cron.d`, in a Kubernetes `CronJob`, in a cloud scheduler or in a CI
  configuration is invisible here, and those are where the worst ones live — no actor, no
  audit, and usually a `rails runner` invocation that steps around every door at once. This
  guard removes the in-repository ways of saying it and cannot reach the others.

  It matches the scheduling libraries it knows by name, so a wrapper of its own is not caught,
  and a cron expression assembled from parts is not caught. It says nothing about whether a
  schedule row's actor is the *right* actor, nor whether the cadence is sane, nor whether the
  route named by a row still exists — a row naming a removed path 404s when it fires, and
  nothing here fires it.
