# frozen_string_literal: true

require "shipshape/source_text"
require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      # Holds `a-command-runs-twice`.
      class CommandsProveIdempotence < Base
        include ReadsKinds

        # Bare, this cost one word; `claimed?` also requires it lead a comment and carry a reason.
        CLAIM = "Idempotent:"

        # Still no proof past this: a false reason this long passes, and that is deliberate.
        MIN_REASON_WORDS = 3

        IDEMPOTENT = <<~RUBY
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

        def on_class(node)
          # `:class` only: including `:module` let `Billing::SettleInvoice` skip the claim.
          return if node.each_ancestor(:class).any?
          return unless one_of?(governed_kinds)

          tests = tests_for(processed_source.file_path)
          return if tests.any? { |path| claimed?(::Shipshape::SourceText.read(path)) }

          add_offense(node.identifier, message: message_for(node.identifier.source, tests))
        end

        private

        # By file name, so a repository filing tests by kind, by path or flat is one case.
        # Indexed once rather than scanned per command: re-globbing and building a Regexp per
        # (command, test file) pair was thirteen seconds at 300 commands and 5,000 test files.
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
            instead: IDEMPOTENT,
          )
        end

        # Must lead a comment line and carry words after it — not sit anywhere in the file.
        def claimed?(text)
          text.each_line.any? { |line| reasoned?(line) }
        end

        def reasoned?(line)
          comment = line.chomp[/\A\s*#\s*(.*)\z/, 1]
          return false unless comment&.start_with?(claim)

          comment[claim.length..].split.length >= MIN_REASON_WORDS
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
