# Decomposing a feature flag — a branch with no owner and no expiry

A procedure, meant to be followed by an agent one step at a time. Every step ends with
something to **run**, because a decomposition nobody can verify is a rewrite with extra
confidence.

The shape: `if Flipper.enabled?(:new_checkout)` in fourteen places. It was added for a rollout
that finished two years ago. Both branches are still there, and nobody can say which one runs
in production without opening an admin page.

**A flag is a decision, and this canon has a lot to say about decisions** — but not this one.
`Shipshape/NoDecisionsInRequestHandling` names a branch on domain state in a controller; a flag
is a branch on *configuration*, usually deeper than the controller, and it is legitimately a
branch while the rollout is happening. What makes it a defect is time, and no cop reads a
calendar.

---

## The cost is multiplicative, which is why this is worth a procedure

Two live flags are four code paths. Three are eight. Ten are a thousand and twenty-four.

**Two of them are tested.** The suite runs with the flags at their default, and perhaps one
test flips one. Every other combination is a configuration that has never been executed
anywhere, and it is reachable in production by two toggles.

That is the argument for deleting flags rather than tidying them: a flag removed is a
dimension removed, and nothing else in this playbook halves the state space with a deletion.

---

## 0. Inventory them with their age, because age is the decision

```sh
grep -rhno "enabled?(:\w*\|Flipper\[:\w*\|feature?(:\w*" app lib | sort -u
```

Then, for each flag, ask git when it arrived:

```sh
git log --reverse --format='%as %s' -S "new_checkout" | head -1
```

**The date is the finding.** A flag added three weeks ago is a rollout in progress. A flag
added two years ago is a branch somebody forgot, and the fact that it still has two sides
means nobody has been able to confirm which side is live.

**Check:** every flag has a first-commit date and a count of call sites.

---

## 1. Determine the live value from production, not from the default

The default in the code is not the answer. A flag is set in a database, a config service, or an
environment variable, and the code's fallback is what applies when that lookup fails — which
may not have been the value in production for a year.

**Ask the system of record.** If nobody can say what a flag's value is in production, that is
itself the finding: an unreadable branch condition, which is
[`nothing-travels-off-the-call-path`](../laws/nothing-travels-off-the-call-path.md) in its
purest form — ambient state deciding what the code does.

**Check:** each flag has a recorded production value, and who told you.

---

## 2. Sort them, and most of them are finished

| State | What to do |
|---|---|
| on everywhere, for months | delete the flag and the **off** branch |
| off everywhere, for months | delete the flag and the **on** branch — the feature was abandoned |
| genuinely per-actor, permanently | it is not a flag, it is a permission or a plan — see below |
| actually rolling out right now | leave it, and write the removal date in the code |

**The third row is the one that gets mislabelled.** "Enterprise customers get the new
dashboard" is not a rollout — it is a product rule that will be true forever, and it belongs in
the permission model or in a column on the account, where it can be read, granted, and
audited. A flag system used for entitlements is a second authorisation model with no audit
trail.

**Check:** every flag has one of the four labels.

---

## 3. Delete the dead branch first, then the flag

Two commits, in this order, and never the reverse:

1. remove the branch that does not run — the code is now unconditional, the flag is still
   consulted and always takes the same path
2. remove the flag call sites and the flag itself

**Doing it in one commit is how the wrong branch gets deleted.** With the dead side removed
first, the diff of step 1 is exactly "here is the code that was not running", which is a thing
a reviewer can check. A combined diff shows a rewrite.

**Check:** after step 1, the suite is green and the flag appears only in conditions that are
now constant. After step 2, `grep` for the flag name returns nothing — including the admin UI,
the seeds, and the test helpers.

---

## 4. Delete the test that pinned the dead branch

A flag with two sides usually has a test per side. Removing the branch and keeping its test
leaves a test asserting behaviour that no longer exists — it will either fail immediately, or
worse, pass against the surviving branch and quietly assert nothing.

**Check:** no test sets the flag; no test name mentions it.

---

## 5. Stop when the live flags are the ones rolling out this month

```sh
shipshape check
```

---

## What this leaves you

**Code whose behaviour can be read from the code.** The number of reachable configurations
falls by half per flag removed, and the ones that remain are the ones somebody is actively
watching.

## What none of this proves

**Nothing here finds a flag that was never a call site.** A flag read once and stored in a
column, a flag consulted in a view template, a flag whose name is built from a string — none of
those are in step 0's grep, and the last one is invisible to every reader.

**And deleting a flag is not reversible in a hurry.** The reason a two-year-old flag still
exists is usually that somebody, once, needed to turn something off at speed. Removing it
removes that ability, and if the feature genuinely still needs a kill switch, the answer is to
keep the flag and write down why — not to leave the question unasked for another year.
