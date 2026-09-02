# frozen_string_literal: true

require "rubocop/cop/shipshape/explains"

module RuboCop
  module Cop
    module Shipshape
      # Holds the mixin half of `a-test-inherits-what-it-needs`: a test shares behaviour by
      # inheriting the one base test class, never by mixing a module into itself.
      class NoTestMixins < Base
        include Explains

        MIXERS = %i[include extend prepend].freeze

        # Ruby's own sharing, never named by this law: mixed in without reopening the one
        # shared surface `a-test-inherits-what-it-needs` closes.
        LANGUAGE_MODULES = %w[Comparable Enumerable Kernel Math Singleton Observable
                               MonitorMixin Forwardable].freeze

        def on_send(node)
          return unless MIXERS.include?(node.method_name)
          return if node.receiver
          return if node.arguments.empty?
          return if node.arguments.all? { |argument| allowed?(argument) }

          add_offense(node, message: message_for(node))
        end

        private

        def allowed?(argument)
          argument.self_type? || (argument.const_type? && LANGUAGE_MODULES.include?(name_of(argument)))
        end

        def name_of(node)
          node.source.sub(/\A::/, "")
        end

        def message_for(node)
          explain(
            "`#{node.method_name} #{node.arguments.map(&:source).join(', ')}` puts behaviour " \
            "on this test from a file the test itself does not mention.",
            because: "A module included here does exactly what it does in an operation: it " \
                     "adds methods from a file nobody reading this class opens. Everything a " \
                     "test needs — an assertion helper, a way to sign in an actor, a way to " \
                     "travel time — is a method on the one base class every test in the " \
                     "suite already inherits, added once and reviewed once.",
            instead: <<~RUBY,
              # the base class gains the method, in the open, reviewed once
              class TestCase < ActiveSupport::TestCase
                def sign_in_as(actor)
                  ...
                end
              end

              class ConfirmBookingTest < TestCase
                def test_it_confirms
                  sign_in_as(admin)
                  ...
                end
              end
            RUBY
          )
        end
      end
    end
  end
end
