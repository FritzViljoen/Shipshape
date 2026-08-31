# `a-comment-is-a-second-copy` — A file carries at most a tenth of its own code in comment

A comment restating a rule is a second copy of that rule. Nothing points at the copy when the
rule changes, so nobody reviews it, and it goes on being believed after it has stopped being
true. A wrong comment is worse than no comment, because it is read as documentation.

**This is not an argument against comments.** A tenth is a real budget, and it buys the two
kinds that say something the code cannot: **why**, where the obvious approach was wrong, and a
**fact about the outside world** the reader cannot derive from the file. What it does not buy
is a paraphrase of a law, which has a home already.

**It was measured, not guessed.** The base classes this gem installs carried 795 comment lines
over 1,087 of code — 66%, and three of them were false. `io_command` described what happened
"after the transaction" it opens none of. `workflow` told views to call `permissions`, which
had been made private. `query` documented an audit entry a query has never written. Each was
true when written and none was reviewed, because the review was on the law.

**The budget is per file, and it is a ceiling on prose, not on thought.** A file that needs
more explanation than a tenth is usually a file whose reasoning belongs in the law it
implements, or code that would be clearer named than described.

- **Principle:** `one-way-to-say-each-thing` governs — the rule has one home, and a paraphrase
  beside the code is the second way to say it. `nothing-fails-quietly` produces the rest: a
  stale comment is a wrong answer nothing reports.
- **Guard:** `Shipshape/CommentBudget`, over every `.rb` file it is pointed at, in this gem
  and in a consuming application. It counts **comment tokens on their own line**, so a `#`
  inside a heredoc — a cop's `instead:` example, a fixture — is code and is not charged.
  Magic comments and `rubocop:` directives are addressed to the tool, not the reader, and are
  not charged either. **The budget is never less than one line**, so a file too small for a
  tenth of a line can still say what it is. Fails the first comment, naming count and budget.
- **Guard's limit:** it counts, and cannot read. Whether the comments that fit are the ones
  worth keeping is a judgement no cop makes: a file may spend its whole budget restating the
  next line and pass. It also sees only Ruby — the `.tt` templates this gem ships are ERB
  until they are installed, and are covered in the application they land in, not here.
