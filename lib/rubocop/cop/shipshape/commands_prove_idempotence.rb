# frozen_string_literal: true

require "shipshape/source_text"
require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      # Holds `a-command-runs-twice` (docs/laws/a-command-runs-twice.md).
      #
      # **`tell-dont-ask` already obliges a command to survive being called twice**, and this
      # is the check that somebody thought about how. A caller may not ask "has this happened
      # already" — branching *is* asking — so it cannot guard the call, and the command must
      # own repetition itself. That obligation exists whether or not anybody noticed it.
      #
      # It stops being theoretical the moment work is deferred: a queue retries, and a command
      # that double-applies turns one retry into two charges.
      #
      # **The append is the case that needs the most thought and gets the least.** A command
      # that settles an invoice can consult `settled_at`; a command that posts a comment has
      # nothing to consult, because two identical comments are both legal. Tell-don't-ask makes
      # it own the decision and hands it nothing to decide on — so idempotence there is a
      # unique index or a key from the caller, and that is a schema change rather than a
      # judgement.
      #
      # **What it checks is that the claim was written**, in the command's own test, naming
      # what makes the second run safe. It cannot check that the test proves anything — the
      # same position `a-guard-states-its-limit` takes about `Watched to fail`, and for the
      # same reason: writing the sentence is the act, and the check makes the act compulsory
      # rather than optional.
      #
      # WHAT IT DOES NOT CATCH: whether the claim is **true**. A command whose test says
      # "Idempotent: the unique index refuses the second row" passes with no such index. It
      # cannot tell a real double-run test from a comment. It finds tests by **file name**, so
      # a command tested from a differently-named file — a shared example, a request spec that
      # covers four commands — reads as untested and is a false positive to be argued rather
      # than suppressed.
      #
      # @example
      #   # bad — no test names how a second run behaves
      #   class SettleInvoice < Command; end
      #
      #   # good — test/commands/settle_invoice_test.rb
      #   # Idempotent: the second call finds settled_at set and answers :already_settled.
      #   def test_settling_twice_settles_once
      class CommandsProveIdempotence < Base
        include ReadsKinds

        # The claim, written where the test is. A phrase rather than a heuristic, because
        # writing it is the act being required — exactly as `Watched to fail` is.
        CLAIM = "Idempotent:"

        def on_class(node)
          # `:class` only, matching the two sibling cops. Including `:module` skipped every
          # command declared inside one — `Billing::SettleInvoice` needed no claim at all,
          # which is most commands in most applications.
          return if node.each_ancestor(:class).any?
          return unless one_of?(governed_kinds)

          tests = tests_for(processed_source.file_path)
          return if tests.any? { |path| ::Shipshape::SourceText.read(path).include?(claim) }

          add_offense(node.identifier, message: message_for(node.identifier.source, tests))
        end

        private

        # By file name, across every declared test root. A command at
        # `app/commands/settle_invoice.rb` is looked for as `settle_invoice_test.rb` or
        # `settle_invoice_spec.rb` anywhere beneath them, so a repository that files its tests
        # by kind, by path, or flat is all one case.
        #
        # **Indexed by name once, not scanned per command.** RuboCop builds a cop per file, so
        # the memo below is per file too — the earlier version re-globbed the whole test tree
        # and built a fresh Regexp for every (command, test file) pair. Measured at 300
        # commands and 5,000 test files, that was thirteen seconds of a lint run.
        def tests_for(path)
          stem = File.basename(path, ".rb")

          tests_by_stem.fetch(stem, [])
        end

        def tests_by_stem
          @tests_by_stem ||= test_files.each_with_object({}) do |file, index|
            stem = File.basename(file)[/\A(.+)_(?:test|spec)\.rb\z/, 1]
            next if stem.nil?

            (index[stem] ||= []) << file
          end
        end

        def test_files
          @test_files ||= test_roots.flat_map { |root| Dir.glob(File.join(base_dir, root, "**", "*_{test,spec}.rb")) }
        end

        def message_for(name, tests)
          found = tests.empty? ? "no test file names it" : "its test does not say"

          explain(
            "`#{name}` does not say what happens when it runs twice — #{found}.",
            because: "`tell-dont-ask` already obliges it: a caller may not ask whether this " \
                     "has happened already, because branching is asking, so the caller " \
                     "cannot guard the call and the command must own repetition itself. That " \
                     "is true today and it becomes load-bearing the moment the work is " \
                     "deferred, because a queue retries — and a command that double-applies " \
                     "turns one retry into two charges. This checks that somebody decided " \
                     "how; it cannot check that they were right.",
            instead: <<~RUBY,
              # in the command's test, naming what makes the second run safe
              # Idempotent: the second call finds settled_at set and answers :already_settled.
              def test_settling_twice_settles_once
                SettleInvoice.call(actor: actor, invoice_id: id)

                assert_equal :already_settled, SettleInvoice.call(actor: actor, invoice_id: id).error
              end

              # an append has nothing to consult — two identical comments are both legal — so
              # its answer is a key, not a judgement
              # Idempotent: the unique index on (author_id, digest) refuses the second row.
            RUBY
          )
        end

        def claim
          @claim ||= cop_config.fetch("Claim", CLAIM)
        end

        def test_roots
          @test_roots ||= cop_config.fetch("TestRoots", %w[test spec])
        end

        def governed_kinds
          cop_config.fetch("Kinds", %w[command io_command legacy_command])
        end

        def base_dir
          config.base_dir_for_path_parameters
        end
      end
    end
  end
end
