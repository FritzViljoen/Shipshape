# frozen_string_literal: true

require "test_helper"
require "shipshape/method_complexity"

# Every repository below carries a second Ruby file (turns `--parallel` on) and every
# measurement below runs twice over it (a warm cache on the second) - the same shape
# `BaseTestClassLinesTest` guards against, and for the same reason: a lone file in a fresh
# `Dir.mktmpdir` is blind to both forking and the cache.
class MethodComplexityTest < Minitest::Test
  RUBOCOP_YML = <<~YAML
    AllCops:
      NewCops: disable
      SuggestExtensions: false
  YAML

  def test_every_non_empty_method_reports_not_only_offenders
    in_repo(RUBOCOP_YML) do |root|
      write(root, "app/models/plain.rb", <<~RUBY)
        class Plain
          def trivial
            1 + 1
          end
        end
      RUBY

      methods = call(root)

      found = methods.find { |method| method.name == "trivial" }
      refute_nil found, "a method scoring under any real Max must still be reported"
      assert_in_delta 1.0, found.complexity
    end
  end

  def test_a_branch_free_chain_of_calls_scores_above_a_branch
    in_repo(RUBOCOP_YML) do |root|
      write(root, "app/models/shapes.rb", <<~RUBY)
        class Shapes
          def chain(a)
            b = a.foo.bar.baz
            c = b.qux.quux
            d = c.corge.grault.garply
            d
          end

          def branch(x)
            if x
              1
            else
              2
            end
          end
        end
      RUBY

      methods = call(root)
      chain = methods.find { |method| method.name == "chain" }
      branch = methods.find { |method| method.name == "branch" }

      assert_operator chain.complexity, :>, branch.complexity,
                       "ABC prices in the call-and-assignment chain a branch count alone misses"
    end
  end

  def test_the_line_is_the_methods_own_definition_line
    in_repo(RUBOCOP_YML) do |root|
      write(root, "app/models/plain.rb", <<~RUBY)
        class Plain
          # a comment above the method
          def trivial
            1 + 1
          end
        end
      RUBY

      found = call(root).find { |method| method.name == "trivial" }

      assert_equal 3, found.line
    end
  end

  # `vendor/**/*` is excluded by RuboCop's own shipped default config regardless of what this
  # class does, so it would pass even with `inherited_config` deleted outright. The generated
  # tree name below is not: it only comes off the target's own `.rubocop.yml`, read back via
  # `inherit_from` because no `config:` was given.
  def test_a_target_repositorys_own_excludes_are_honoured_by_default
    in_repo(RUBOCOP_YML) do |root|
      write(root, "app/models/plain.rb", "class Plain\n  def trivial\n    1 + 1\n  end\nend\n")
      write(root, "app/generated/plain.rb", "class Generated\n  def trivial\n    1 + 1\n  end\nend\n")
      File.write(File.join(root, ".rubocop.yml"), <<~YAML)
        AllCops:
          NewCops: disable
          SuggestExtensions: false
          Exclude:
            - 'app/generated/**/*'
      YAML

      methods = Shipshape::MethodComplexity.new(directory: root).call

      refute_includes methods.map(&:file), "app/generated/plain.rb"
      assert_includes methods.map(&:file), "app/models/plain.rb"
    end
  end

  def test_a_forced_max_beats_whatever_the_target_configured
    in_repo(<<~YAML) do |root|
      AllCops:
        NewCops: disable
        SuggestExtensions: false

      Metrics/AbcSize:
        Max: 999
    YAML
      write(root, "app/models/plain.rb", "class Plain\n  def trivial\n    1 + 1\n  end\nend\n")

      refute_empty call(root), "the target's own generous Max must not silence every method"
    end
  end

  def test_comments_and_blank_lines_do_not_move_the_number
    in_repo(RUBOCOP_YML) do |root|
      write(root, "app/models/plain.rb", <<~RUBY)
        class Plain
          def busy(x)
            if x > 1
              foo(x)
            elsif x < 0
              bar(x)
            else
              baz(x)
            end
          end
        end
      RUBY

      before = call(root).find { |method| method.name == "busy" }.complexity

      write(root, "app/models/plain.rb", <<~RUBY)
        # a leading comment that says nothing about the code

        class Plain

          # this method decides between three outcomes

          def busy(x)


            if x > 1
              foo(x)
            elsif x < 0
              bar(x)
            else
              baz(x)
            end
          end
        end
      RUBY

      after = call(root).find { |method| method.name == "busy" }.complexity

      assert_in_delta before, after, 0.0001,
                       "formatting must not move a number this class means to ratchet"
    end
  end

  private

  def call(root)
    complexity = Shipshape::MethodComplexity.new(directory: root, config: File.join(root, ".rubocop.yml"))

    cold = complexity.call
    warm = complexity.call

    assert_equal cold, warm, "a second, warm-cache run over the same directory must agree with the first"

    warm
  end

  def write(root, path, contents)
    full = File.join(root, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, contents)
  end

  def in_repo(config)
    Dir.mktmpdir("shipshape-complexity") do |root|
      File.write(File.join(root, ".rubocop.yml"), config)
      write(root, "companion.rb", "class Companion\nend\n")
      yield(root)
    end
  end
end
