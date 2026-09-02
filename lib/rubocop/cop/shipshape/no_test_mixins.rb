# frozen_string_literal: true

require "rubocop/cop/shipshape/explains"
require "rubocop/cop/shipshape/reads_kinds"
require "shipshape/kinds"
require "shipshape/settings"

module RuboCop
  module Cop
    module Shipshape
      # Holds the mixin half of `a-test-inherits-what-it-needs`: an offence only when the mixin
      # resolves to a file this repository's own test tree owns — a gem's module, or an
      # expression this cop cannot name, passes untouched.
      class NoTestMixins < Base
        include Explains
        include ReadsKinds

        MIXERS = %i[include extend prepend].freeze

        # Ruby's own sharing, never named by this law.
        LANGUAGE_MODULES = %w[Comparable Enumerable Kernel Math Singleton Observable
                               MonitorMixin Forwardable].freeze

        # A bucket name for `Kinds` to search, over this cop's own `Include` globs.
        OWNED_KIND = "test_owned"

        INSTEAD = <<~RUBY
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

        def on_send(node)
          return unless MIXERS.include?(node.method_name)
          return if node.receiver
          return if node.arguments.empty?
          return if node.arguments.all? { |argument| allowed?(argument) }

          add_offense(node, message: message_for(node))
        end

        private

        def allowed?(argument)
          return true if argument.const_type? && LANGUAGE_MODULES.include?(name_of(argument))

          # `extend self` is the one-line refactor out of `include SharedSetup`.
          return false if argument.self_type?

          name = resolvable_name(argument)
          name.nil? || !owned_locally?(name)
        end

        def resolvable_name(argument)
          return name_of(argument) if argument.const_type?
          return root_constant(argument) if chain?(argument)

          nil
        end

        def chain?(node)
          node.respond_to?(:send_type?) && (node.send_type? || node.csend_type?)
        end

        # Resolved by where the constant's file would live, never by a hand-kept module list.
        def owned_locally?(name)
          !owned_kinds.file_for_constant(name).nil?
        end

        def owned_kinds
          @owned_kinds ||= ::Shipshape::Kinds.new(
            settings: ::Shipshape::Settings.new(kinds: { OWNED_KIND => Array(cop_config["Include"]) }, matrix: {}),
            base_dir: base_dir,
          )
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
            instead: INSTEAD,
          )
        end
      end
    end
  end
end
