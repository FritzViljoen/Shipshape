# frozen_string_literal: true

require "test_helper"
require "open3"

# **The removals, actually performed.**
class RemovalTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  STUB = <<~RUBY
    # Neuter one cop: it still runs, still walks the AST, and reports nothing.
    require "shipshape"
    RuboCop::Cop::Shipshape.const_get(ENV.fetch("NEUTER")).class_eval do
      def add_offense(*, **); end
    end
  RUBY

  def test_every_cop_test_fails_when_its_cop_reports_nothing
    stub = Tempfile.new(["neuter", ".rb"])
    stub.write(STUB)
    stub.close

    unproven = cops.reject { |cop| neutered_run_fails?(cop, stub.path) }

    assert_empty unproven,
                 "These cops report nothing and their tests still pass, so the tests do not " \
                 "exercise the cop. A guard nobody has watched fail may enforce nothing."
  ensure
    stub&.unlink
  end

  private

  def cops
    RuboCop::Cop::Registry.global.cops
                          .map(&:cop_name)
                          .grep(%r{\AShipshape/})
                          .map { |name| name.split("/").last }
                          .select { |cop| File.exist?(test_for(cop)) }
                          .sort
  end

  def neutered_run_fails?(cop, stub)
    _out, _err, status = Open3.capture3(
      { "NEUTER" => cop },
      RbConfig.ruby, "-I#{File.join(ROOT, 'lib')}", "-I#{File.join(ROOT, 'test')}",
      "-r", stub, test_for(cop),
      chdir: ROOT,
    )

    !status.success?
  end

  def test_for(cop)
    snake = cop.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase

    File.join(ROOT, "test/rubocop/cop/shipshape/#{snake}_test.rb")
  end
end
