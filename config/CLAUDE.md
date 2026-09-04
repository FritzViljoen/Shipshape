# CLAUDE.md — `config/`

One file, `default.yml`: every cop's RuboCop config block, read by the gem itself, by
`shipshape rules`, and by `test/canon_test.rb`. No README pairs with this folder — the file's
own inline comments carry the reasoning, and this restates only what a check enforces.

## `Shipshape/CallGraph` is the one place globs live

Every kind's paths (`app/deeds/**/*.rb`, and so on) are declared once, under
`Shipshape/CallGraph.Kinds`. A cop scoped by kind lists **kind names**
(`Kinds: [deed, question]`), never its own globs — "the layout is declared once ... and read
from there" is the comment on the file itself, and duplicating a glob into a second cop's block
is the second copy `one-way-to-say-each-thing` forbids. `BaseClasses` maps each kind name to
the constants that count as inheriting it, consumed by `KindIsInheritedNotOnlyPlaced` and by
`test/canon_test.rb`'s check that every base class including `TypedArguments` names a kind the
`Shipshape/TypedArguments` cop actually covers.

## A concerns directory needs its own line beside the tree it belongs to

A glob ending in a filename suffix (`**/*_controller.rb`) cannot match a concern directory, and
a concern included into a kind **is** that kind — `test/canon_test.rb`'s
`test_every_governed_tree_governs_its_concerns` derives this from the globs themselves and
fails if a kind's root directory (`app/<root>/`) has no matching `app/<root>/concerns/**/*.rb`
entry somewhere in `Kinds`. Adding a new kind means adding its concerns glob in the same edit,
not a follow-up.

## Every key here is claimed on both sides

`test/canon_test.rb` reads every law's `- **Guard:**` line and asserts each named
`Shipshape/*` cop has a config block, and — separately — that every config block's cop is named
by some law. Adding a top-level key with no corresponding law, or a law naming a key that has
none, fails the build the same way an unregistered cop does.

## Never cite by number

The inline prose in this file explains real decisions (why a kind is or isn't here, why a base
class is or isn't listed) — write the reason, never point at a rule by its ordinal position.
