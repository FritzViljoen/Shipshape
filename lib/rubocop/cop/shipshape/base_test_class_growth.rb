# frozen_string_literal: true

require "rubocop/cop/shipshape/explains"

module RuboCop
  module Cop
    module Shipshape
      # Holds the ratchet half of `a-test-inherits-what-it-needs`. Every class here is a base
      # or support class, never a leaf test, so every definition it holds is flagged - not
      # because one is wrong, but so `shipshape check` has an offence count to compare against
      # the merge base for the count of definitions, and a line count for the class's size.
      class BaseTestClassGrowth < Base
        include Explains

        READERS = %i[attr_reader attr_accessor attr_writer].freeze
        LIFECYCLE = %i[setup teardown].freeze

        def on_class(node)
          body = node.body
          return if body.nil?

          statements = body.begin_type? ? body.children : [body]
          statements.each { |statement| check(statement) }
        end

        private

        def check(node)
          kind = kind_of(node)
          return if kind.nil?

          add_offense(node, message: message_for(node, kind))
        end

        def kind_of(node)
          return "a method" if method?(node)
          return "a constant" if node.respond_to?(:casgn_type?) && node.casgn_type?
          return "a reader" if reader?(node)
          return "a setup or teardown block" if lifecycle?(node)

          nil
        end

        def method?(node)
          node.respond_to?(:def_type?) && (node.def_type? || node.defs_type?)
        end

        def reader?(node)
          send?(node) && node.receiver.nil? && READERS.include?(node.method_name)
        end

        def lifecycle?(node)
          candidate = node.respond_to?(:block_type?) && node.block_type? ? node.send_node : node

          send?(candidate) && candidate.receiver.nil? && LIFECYCLE.include?(candidate.method_name)
        end

        def send?(node)
          node.respond_to?(:send_type?) && node.send_type?
        end

        def message_for(node, kind)
          explain(
            "This base test class holds one more definition: `#{node.source.lines.first.strip}`, " \
            "#{kind}.",
            because: "Every test in the suite inherits this class, so a method added here is " \
                     "added to all of them, in a diff nobody but this file's reviewer sees. " \
                     "`shipshape check` compares this cop's offence count, and the class's " \
                     "line count, against the merge base - both may only fall, so a real need " \
                     "still lands, and a need that was never reviewed does not land quietly.",
            instead: <<~RUBY,
              # a genuine addition still lands here - reviewed once, used by every test after
              class TestCase < ActiveSupport::TestCase
                def sign_in_as(actor)
                  ...
                end
              end

              # a helper only one test needs stays in that test, confessed rather than shared
              class ConfirmBookingTest < TestCase
                def test_it_confirms
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
