# Patterns people reach for — agent copy

[`rails-patterns.md`](rails-patterns.md) is the document. This governs nothing. On conflict, the
human copy wins.

An operation is sized by **authorisation** — permitted or refused whole, no bigger. Split by
**direction** — one thing writes, one reads. Most verdicts below follow from those two.

| verdict | means |
|---|---|
| **Is this** | shipshape is the pattern, failure mode guarded |
| **Instead** | different answer, same need |
| **Refused** | do not |
| **Out of scope** | not about the shape of code |
| **Complementary** | another tool's job |

| pattern | verdict | write instead |
|---|---|---|
| Service objects | Is this | `Command` / `Query`. Sister calls refused before the matrix is read |
| Result objects | Is this | command answers `Result`. Query answers shapes, no envelope |
| Value objects | Is this | `Shape`. Takes records out of the view |
| Query objects | Is this, one disagreement | answer **shapes, not relations**. Caller cannot chain |
| Form objects | Instead | the operation's constructor is the form object |
| Policy objects | Instead | a permission **is** the class name |
| Presenters / decorators | Refused | markup → component. Logic → operation. Formatting → the type |
| Concerns | Instead | a mixin declares no public method |
| Interactor / dry-transaction | Is this, minus the DSL | `Workflow`, plain Ruby, in your repo |
| State machines | Instead | derive state from event rows |
| Observers / pub-sub | Refused | one workflow, one file, in order |
| Repository pattern | Refused | record maps rows. Query reads with the framework, answers shapes |
| Rails engines | Out of scope | packaging, not shape |
| Packwerk / packs | Complementary | it bounds packages. This bounds what a class may be |
| CQRS | Is this, tenth of the cost | split at the operation. One table, one record class |
| Event sourcing | Refused, one exception | ask what is lost if the log is dropped |
| Hexagonal / clean | Refused | a record is the mapping. Adapters are `io_command`, `io_query` |
| Micro-services early | Out of scope | boundary without the network |
| DCI | Refused by the shape | nothing to mix a role into |

## Rules for you

Do not quote a verdict as coverage. Four things here are deliberately unguarded: a flat
directory of 400 operations, `.erb` templates (no cop reads them), `extend` at runtime, and the
`actor.may?` lookup.

Check the human copy before telling anyone a pattern is caught.

## Not here

Where each pattern goes wrong, which is why the verdict is what it is. See
[`rails-patterns.md`](rails-patterns.md).
