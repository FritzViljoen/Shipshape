# Characterising the edges — the step before every other step

A procedure, meant to be followed by an agent one step at a time. Every step ends with
something to **run**, because a decomposition nobody can verify is a rewrite with extra
confidence.

**Every other procedure here ends with the same admission: nothing it does proves the code
still works.** `shipshape check` proves the offence count fell. Split a service into six
operations and every check goes green whether or not the behaviour survived.

This is the answer, and it is the reason it comes first.

---

## 0. The repository is a black box, and the edges are its surface

**Treat what you are refactoring as a black box.** Not "mostly a black box" — every procedure
in this playbook moves internals, so a test written against an internal moves with it. A test
that asserts `StoryService#build` returns something is deleted by the extraction it was meant
to protect, and its passing tells you only that you updated it.

The edges are what must not change:

- a **request** — a route, a controller action
- an **entry point** — a job, a mailbox, a scheduled task

A refactor changes what is behind an edge, never what the edge answers. `POST /messages` with
these params returned a 302 to `/messages` and sent one email; after the work it does the same,
or the work is wrong. That sentence survives every procedure here, which is what makes it worth
writing down before any of them start.

---

## 1. Find the edges nothing names

```sh
shipshape edges
```

The layout already declares where they are — `request_handling` and `entry_point` are kinds,
so an application that told `Shipshape/CallGraph` where its controllers and jobs live is not
asked twice.

```
54 edges, 210 actions.

NOT NAMED BY ANY TEST — characterise these before moving anything behind them:
  app/controllers/settings_controller.rb    index, deactivate, update, twofa, twofa_auth, …
```

**It asks by class, not by action**, and that was measured rather than assumed: a request spec
says `get "/stories"`, a controller spec says `describe StoriesController`, and almost none of
them name the action. Matching `show` against a suite answers yes for any file containing the
word — the flattering answer, and the dangerous one.

**Check:** the count is a number you recognise. If it is zero, check that a tree is declared —
until one is, nothing looks at it and this reports a clean zero.

---

## 2. Write the test that records what happens, not what should

A characterisation test is not a specification. It does not say what the code *ought* to do; it
records what it *does*, including the parts that look wrong.

```ruby
# Characterisation. Recorded 2026-08-30, before extracting SendMessage.
# Not a specification: the redirect target and the flash wording are what the code does today.
test "posting a valid message redirects to the index and sends one notification" do
  assert_difference -> { Message.count } do
    post "/messages", params: { message: { recipient_username: "alice", subject: "hi", body: "…" } }
  end

  assert_redirected_to "/messages"
  assert_equal 1, enqueued_jobs.size
end
```

**Record the behaviour you disagree with.** A bug you preserve is a bug you can fix
deliberately, later, in a change that says so. A bug you accidentally fix during a refactor is
indistinguishable from a bug you accidentally introduced — and both arrive in a diff that
claims to change nothing.

**Check:** the test passes against the code *as it is now*, before anything moves. A
characterisation test written after the change records the change.

---

## 3. Cover the failure path, because that is what refactors break

The happy path is usually already tested. The path that breaks is the other one: invalid input,
a refused permission, a record that was not found.

Every wall in [a form that fails](a-form-that-fails.md) is on the failure path — the invalid
record that could not come back, the form that needed its errors. If nothing records what the
failure path renders today, nothing will notice when it stops rendering it.

**Check:** for each edge you are about to work behind, a test posts something invalid and
asserts what comes back.

---

## 4. Only now, start the procedure the shape calls for

With the edge recorded, everything else in this playbook is safe to attempt, because the thing
that says you broke it is not one of the things you are moving.

`shipshape next` ranks files by how much of them the suite names — but that is *method*
coverage on the file being changed, which is a weaker signal than this one and answers a
different question: "will anything notice", not "is the outside contract held".

**Check:** the edge test still passes after each slice, not only at the end.

---

## What none of this proves

**A test that names a class is not a test that characterises it**, and `shipshape edges` cannot
tell the difference — it reports that something in the suite mentions `StoriesController`, not
that anything asserts what `GET /stories` returns. The command narrows where to look; it does
not certify what it finds.

It reads names, so an edge exercised only through a shared example, a factory, or a route it
does not spell out reads as uncovered — a false alarm, and the safe direction to be wrong in.

And an edge is not the whole surface. A scheduled task nobody has declared as a kind, an
external service calling in, a database trigger, a message consumer in another repository —
none of those are here, and a refactor can break all of them. The list is a floor.
