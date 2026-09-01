# frozen_string_literal: true

require "test_helper"

# Watched to fail: emptying `SUFFIX` reddens every offence test below; removing the
# `base_class?` guard (return `false` unconditionally) reddens
# `test_the_base_class_itself_is_not_an_offence`.
class NoTypeSuffixTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::NoTypeSuffix

  LAYOUT = {
    "Shipshape/CallGraph" => {
      "Kinds" => {
        "command" => ["app/commands/**/*.rb"],
        "request_handling" => ["app/controllers/**/*_controller.rb"],
      },
      "Matrix" => { "command" => [], "request_handling" => ["command"] },
      "BaseClasses" => { "command" => ["Command"] },
    },
  }.freeze

  COMMAND = "app/commands/settle_invoice.rb"

  def test_a_service_suffix_is_an_offence
    found = check(<<~RUBY)
      class SettleInvoiceService < Command
        def call; end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`SettleInvoiceService` ends in `Service`"
  end

  def test_the_offence_carries_the_reason_and_an_example
    message = check(<<~RUBY).first.message
      class SettleInvoiceManager < Command
        def call; end
      end
    RUBY

    assert_includes message, "WHY: The suffix restates"
    assert_includes message, "INSTEAD:"
    assert_includes message, "class SettleInvoice < Command"
  end

  def test_every_suffix_in_the_family_is_caught
    found = check(<<~RUBY)
      class First < Command; end
      class Second < Command; end
      class Third < Command; end
      class Fourth < Command; end
      class Fifth < Command; end
      class Sixth < Command; end
      class Seventh < Command; end
    RUBY

    # Renamed below to carry each banned suffix, one per class.
    names = %w[FirstService SecondManager ThirdInteractor FourthHandler FifthCommand
               SixthQuery SeventhWorkflow]
    source = names.map { |name| "class #{name} < Command\n  def call; end\nend" }.join("\n")

    assert_equal names.length, check(source).length
  end

  def test_the_base_class_itself_is_not_an_offence
    assert_empty check(<<~RUBY)
      class Command
        def self.call(**arguments)
          new(**arguments).call
        end
      end
    RUBY
  end

  def test_a_name_that_only_contains_the_word_is_not_an_offence
    assert_empty check(<<~RUBY)
      class CommandCenter < Command
        def call; end
      end
    RUBY
  end

  def test_an_ungoverned_kind_is_left_alone
    assert_empty offences(<<~RUBY, cop_class: COP, path: "app/controllers/invoices_controller.rb", other_cops: LAYOUT)
      class InvoicesService < ApplicationController
        def show; end
      end
    RUBY
  end

  private

  def check(source)
    offences(source, cop_class: COP, path: COMMAND, other_cops: LAYOUT)
  end
end
