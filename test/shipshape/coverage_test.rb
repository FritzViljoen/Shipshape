# frozen_string_literal: true

require "test_helper"
require "shipshape/coverage"

# Watched to fail: make `ignored?` answer false and the vendored-tree test reddens; glob only
# the declared roots in `files` and the engine-monorepo test reddens, which is the exact
# flattering answer this class exists to refuse.
#
# The denominator is the whole repository on purpose. Measuring only the trees the layout
# names answers "is what I declared declared" — an engine monorepo keeping everything at
# `core/app/models` would report 100% while nothing was inspected. That is not hypothetical:
# it is what solidus did, reporting nineteen offences over 1203 files it never opened.
class CoverageTest < Minitest::Test
  LAYOUT = {
    "Shipshape/CallGraph" => {
      "Kinds" => { "command" => ["app/commands/**/*.rb"], "record" => ["app/records/**/*_record.rb"] },
      "BaseClasses" => { "command" => ["Command"], "record" => ["ApplicationRecord"] },
      "Matrix" => { "command" => ["record"], "record" => [] },
    },
  }.freeze

  def test_it_counts_what_resolves_to_a_kind
    result = measure(
      "app/commands/settle.rb" => "class Settle < Command\nend\n",
      "app/records/thing_record.rb" => "class ThingRecord < ApplicationRecord\nend\n",
    )

    assert_equal 2, result.total
    assert_equal 2, result.governed
    assert_equal 100, result.percentage
  end

  def test_an_engine_monorepo_reports_nothing_governed
    result = measure(
      "core/app/models/spree/order.rb" => "module Spree\n  class Order\n  end\nend\n",
      "backend/app/controllers/spree/admin_controller.rb" => "class AdminController\nend\n",
    )

    assert_equal 2, result.total
    assert_equal 0, result.governed
    assert_equal 0, result.percentage
    assert_includes result.ungoverned, "core/app/models/spree/order.rb",
      "The failure this exists for: everything looks clean because nothing was inspected."
  end

  def test_it_names_what_no_cop_can_reach
    result = measure(
      "app/commands/settle.rb" => "class Settle < Command\nend\n",
      "app/services/legacy_thing.rb" => "class LegacyThing\nend\n",
    )

    assert_equal ["app/services/legacy_thing.rb"], result.ungoverned
  end

  def test_vendored_and_generated_trees_are_not_the_denominator
    result = measure(
      "app/commands/settle.rb" => "class Settle < Command\nend\n",
      "vendor/bundle/gem.rb" => "class Vendored\nend\n",
      "test/commands/settle_test.rb" => "class SettleTest\nend\n",
      "config/routes.rb" => "Rails.application.routes.draw {}\n",
    )

    assert_equal 1, result.total,
      "Vendored code is somebody else's, and counting it would make every repository look worse than it is for a reason nobody can act on."
  end

  private

  def measure(files)
    Dir.mktmpdir("coverage") do |root|
      files.each do |relative, source|
        target = File.join(root, relative)
        FileUtils.mkdir_p(File.dirname(target))
        File.write(target, source)
      end

      config = RuboCop::Config.new(LAYOUT, File.join(root, ".rubocop.yml"))
      Shipshape::Coverage.new(config: config, root: root).call
    end
  end
end
