# CLAUDE.md — `test/`

Minitest. This suite tests the tool, not an application under the canon —
`a-test-inherits-what-it-needs` and `no-test-factories` (`docs/laws/`) describe what
`Shipshape/NoTestMixins` and `Shipshape/NoTestFactories` enforce on a repository that installs
this gem. **They do not bind this directory.** `include CopRunner` in nearly every file under
`test/rubocop/cop/shipshape/` is the deliberate shared-helper shape those laws forbid elsewhere
— correct here, because this gem is not governed by its own cops (root `CLAUDE.md`). Do not
"fix" a test file's `include` to satisfy a law whose guard never runs against this tree.

## Every cop test: `include CopRunner`, call `offences(...)`

`test_helper.rb` defines `CopRunner#offences(source, cop_class:, path:, cop_config: {},
files: [], other_cops: {})` — runs one cop over one source string in a throwaway directory and
returns its offences. `files:` writes real bodies, not empty placeholders, when the cop's
`Kinds` resolution depends on a superclass — an empty file has no superclass and quietly tests
the path-only fallback instead of the case you meant to cover.

## `test/canaries/` is generated — never hand-edit it

Everything under here, including `.rubocop.yml`, is written by `shipshape canaries --plant`
and checked by `test/canaries_test.rb` against what the planter would write right now. A stray
hand-edit reads as drift and fails `test_the_checked_in_configuration_is_what_the_planter_writes`
or `test_the_checked_in_canaries_match_what_the_planter_writes`. Add a cop's canary by adding it
to `Shipshape::Canaries::PLANTED` and re-planting, not by writing a file here directly.

**A canary proves a cop can fire once — never that it fires on everything its law describes.**
Write the planted violation from the law's own text, not by copying a case the cop's own unit
test already covers; a cop narrowed to the shape of its own test and its own canary passes
every check this gem has and protects nothing further. It has happened three times.

## Every cop test needs a `Watched to fail` comment naming a real removal

Not aspirational — actually break the cop (comment out a branch, blank a constant, weaken a
regex), run the test, watch it go red, then restore the cop and write down which mutation
reddened which assertion. `test/canon_test.rb`'s
`test_every_cop_test_names_the_removals_that_proved_it` only checks the phrase is present; it
cannot check the removal was real. `test/removal_test.rb` is the one guard that re-derives this
by actually neutering every cop's `add_offense` and running its test file in a subprocess —
slow enough that it is not in the default `rake` task; run it by hand
(`bundle exec rake test:removal`) after touching any cop.

## A test method hidden below `private`/`protected` never runs, and reads as passing

Minitest only collects public `test_*` methods. It has happened twice, in different files, and
the only thing that catches it is `test/no_hidden_test_methods_test.rb` scanning every loaded
`Minitest::Test` subclass's private and protected methods for a zero-arity `test_*` name. If a
new helper method in a cop test file needs to start with `test_` for readability, it must stay
public or be renamed — `private` below it is the actual mistake, not a style choice.

## Never cite a rule by number here

A comment or assertion message naming a rule by its ordinal position instead of its own name is
exactly what `test/documents_have_one_shape_test.rb` forbids in the documents themselves; hold
test code and messages to the same standard even though nothing currently scans `test/` for it.
