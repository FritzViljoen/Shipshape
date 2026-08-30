# Decomposing a generated interface — the method a reader greps for and never finds

A procedure, meant to be followed by an agent one step at a time. Every step ends with
something to **run**, because a decomposition nobody can verify is a rewrite with extra
confidence.

The shape:

```ruby
%w[draft pending settled].each do |state|
  define_method("#{state}?") { status == state }
end

def method_missing(name, *args)
  return @attributes[name] if @attributes.key?(name)

  super
end
```

293 across seven repositories. **The defect is not the metaprogramming; it is that
`settled?` cannot be found.** A reader greps, finds nothing, and concludes the method does not
exist — which is the one thing the codebase should never be able to do to somebody.

---

## 0. Separate the framework's conventions from this repository's

```sh
shipshape next --json
```

`NoGeneratedInterfaces` exempts the framework's public conventions and nothing else, and the
distinction is the whole procedure:

- `has_many`, `validates`, `scope`, `belongs_to` — **a corpus of every Rails application.** A
  reader who does not know them can look them up, and the answer is the same everywhere.
- `acts_as_thing`, `has_settings`, a `define_method` loop in `app/` — **a corpus of one
  repository.** The only documentation is the generator, and finding the generator requires
  already knowing it exists.

**Check:** every remaining offence is a convention this repository invented.

---

## 1. Count the generated methods before deciding anything

```ruby
%w[draft pending settled].each { |s| define_method("#{s}?") { status == s } }
```

Three methods, each one line. **Write them out.** Three explicit predicates are shorter to
read than the loop, greppable, and the diff is the last one this code needs.

The instinct to keep the loop is an instinct about writing, not reading — and this canon is
about the second, because writing code stopped being the scarce thing and knowing a change is
finished did not.

**The number that changes the answer is roughly a dozen.** Below it, always write them out.
Above it, the list is data and the loop was a symptom — go to step 2.

**Check:** `grep -rn "def settled?" app` finds the method, which is the whole point.

---

## 2. A long list is a table, not a loop

```ruby
CARRIERS.each do |carrier|
  define_method("#{carrier}_tracking_url") { ... }
end
```

Forty generated methods is not a metaprogramming problem. **It is `no-industry-terms-in-code`
in a different costume**: the carriers are a row per carrier, and the reason there is a loop is
that somebody noticed the repetition without noticing the data.

The fix is the same as everywhere in this canon — the list moves to a table, and the forty
methods become one method taking a carrier. See [the index](README.md) for the test of what
belongs in a table: **who do you ask when it is wrong?** If the answer is a person outside the
team, it is a row.

**Check:** "Rules that are really data" falls in `shipshape report`, and the `define_method`
is gone rather than relocated.

---

## 3. `method_missing` is a different animal — it is a missing type

```ruby
def method_missing(name, *args)
  return @attributes[name] if @attributes.key?(name)

  super
end
```

This is not a shortcut for methods; it is an object with **no declared shape at all**. Anything
can be asked of it and the answer depends on runtime data, so nothing can be asserted, nothing
can be documented, and a typo is a `NoMethodError` at whatever hour that branch first runs.

The replacement is a shape: named fields, asserted at construction. That is
`arguments-are-typed-at-construction` and it is exactly what a `@attributes` hash was avoiding.

**If the keys genuinely are not known until runtime** — a webhook payload, a user-defined
form — then the object is a `Hash` and should say so. Wrapping a hash in an object that
pretends to have methods is the worst of both: no type, and no honest signature either.

**Check:** `NoGeneratedInterfaces` is silent, and the class either has named fields or is a
plain `Hash`.

---

## 4. Delete the generator last

The order that works: write the explicit methods, run the suite, **then** delete the loop.

Both alive at once is legal in Ruby — the explicit `def` wins over an earlier
`define_method` — so the intermediate state is safe and testable. Deleting first and writing
after leaves a window where the methods do not exist, and Ruby will not tell you until
something calls one.

**Check:** `shipshape check` — the count falls at each slice and never rises.

---

## 5. `send` goes with it

A generated interface is usually reached by a generated call:

```ruby
record.send("#{state}?")
```

`NoGeneratedInterfaces` names `send`, `__send__` and `public_send` for the same reason it names
`define_method` — a method called through a variable is one nobody can grep for either. Once
the predicates are explicit, the call site can name one.

**Check:** `grep -rn "\.send(\"" app lib` returns nothing that names a method this procedure
just wrote out.

---

## What none of this proves

**Nothing here shows you found every generated method.** A `define_method` over a constant
defined in another file, or over a database query, generates a set nothing static can
enumerate — and the explicit methods you wrote are the ones you *knew about*.

The reliable failure: **a method that existed only when the data contained a particular
row**, called from somewhere nothing tests. It disappears with the loop and nothing says so.
Before deleting a generator driven by anything other than a literal array, list what it
produces at runtime — `Klass.instance_methods(false).sort` in a console — and diff that against
what you wrote.
