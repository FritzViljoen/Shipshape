# Decomposing an unowned find — the row exists, so it was returned

A procedure, meant to be followed by an agent one step at a time. Every step ends with
something to **run**, because a decomposition nobody can verify is a rewrite with extra
confidence.

**What you are aiming at:**

```ruby
# before — the row is fetched, then judged
story = Story.find(@id)
return failure(:forbidden) unless story.user_id == actor.id

# after — a row that is not the actor's is not found
story = actor.stories.find_by(id: @id)
return failure(:not_found) unless story
```

Ownership moves into the load, so there is no window in which the operation holds a row it may
not have. `:not_found` rather than `:forbidden` is deliberate: a refusal that distinguishes the
two tells a stranger the row exists.

The shape: `Story.find(params[:id])`. The row exists, so it comes back. Whether it is *this
actor's* row was never asked, and nothing in the code records that the question was skipped
rather than answered.

**This is the one security failure the canon's own permission model cannot hold, and the
reason is deliberate.** [`a-permission-is-the-class-name`](../laws/a-permission-is-the-class-name.md)
makes a permission a *class*: `:UpdateStory` says this actor may update stories. It does not
say *which* stories, and it never can — a class name has no room for a row in it.

So `Shipshape/EveryDoorChecksPermission` passes, `NoUnparsedLookup` passes once the id is
parsed, and the actor who may update stories updates yours. **Type-level authorisation is
complete and row-level ownership is entirely outside it.** That gap is the subject here.

---

## 0. Find the loads that take an id from outside

```sh
grep -rn "\.find(\|\.find_by(\|\.find_by_id\|\.where(id:" app/questions app/deeds app/io_questions app/io_deeds
```

Then narrow to the ones whose id came from a keyword argument rather than from another row
this operation already owns. An id the operation computed itself is not this shape; an id the
caller handed in is.

**Check:** you have a list of operations that load by a caller-supplied id, and for each one
you can say what the id names.

---

## 1. Ask the ownership question once per operation, and write the answer down

For each: **whose is this row?**

| Answer | What it means |
|---|---|
| "the actor's own" | scope the load — step 2 |
| "the actor's organisation's" | scope the load through the organisation |
| "anybody's — it is public" | no scoping, and say so in a comment, because the next reader will ask |
| "an administrator sees all" | that is a different operation with a different permission, not a branch in this one |

**The last row is the one that goes wrong.** `if actor.admin? then Story.find(id) else
actor.stories.find(id)` is a decision about who may see what, expressed as a branch — two
operations sharing a class, which is
[`one-operation-one-class`](../laws/one-operation-one-class.md). Split them and the permission
model does the work it was built for.

**Check:** every operation on the list has one of the four answers, recorded.

---

## 2. Scope the load. Do not check after loading.

```ruby
# before — the row is fetched, then judged
story = Story.find(@id)
return failure(:forbidden) unless story.user_id == actor.id

# after — a row that is not the actor's is not found
story = actor.stories.find_by(id: @id)
return failure(:not_found) unless story
```

**These differ in more than style.** The first has the row in hand before deciding, so every
line added after the fetch and before the check is a chance to use it — logging it, counting
it, returning a field from it in an error message. The second cannot leak what it did not
load.

**It also collapses two failure modes into one.** "No such row" and "not yours" become the
same answer, which is what you want: distinguishing them tells an attacker which ids exist.

**Check:** no operation on the list fetches a row and then compares an owner field.

---

## 3. Answer `:not_found`, and mean it

Returning `:forbidden` for a row the actor does not own confirms the row exists. That is an
enumeration oracle: walk the ids, and the 403s map the data.

`:not_found` is the honest answer *from this actor's point of view*, which is the only point of
view an operation has.

**Check:** the operation's failure code is the same for a missing row and an unowned one.

---

## 4. Test it with a second actor, because nothing else will

```ruby
test "another actor's story is not found" do
  mine = create_story(owner: alice)

  result = UpdateStory.call(actor: bob, id: mine.id, title: "x")

  refute_predicate result, :success?
  assert_equal :not_found, result.error
end
```

**This test is the whole guard.** There is no cop for it: a cop reading
`actor.stories.find_by(id: @id)` cannot tell whether `stories` is scoped to the actor or is an
association that happens to be named that way, and one that guessed would fail correct code.

**Check:** every operation on the list has this test, with a real second actor.

---

## 5. Stop when every caller-supplied id is loaded through an owner

```sh
shipshape check
```

The count that falls here is not a cop's. It is the length of your list from step 0, and you
are done when every entry has an answer from step 1 and a test from step 4.

---

## What this leaves you

**An operation that cannot return a row the actor has no claim to**, because it never loaded
one. Ownership stops being a check somebody remembers and becomes the shape of the question.

## What none of this proves

**Nothing enumerates the operations that should have an owner.** Step 0 finds loads by id;
whether a given row *has* an owner is a domain question no grep answers, and an operation
correctly scoped to the wrong owner passes every check here.

**And the association is trusted.** `actor.stories` is scoped only if `has_many :stories` means
what it looks like. A `has_many` through a join that itself has no owner is this same defect
one table further away, and this procedure will not see it — follow the association to the
foreign key before believing it.
