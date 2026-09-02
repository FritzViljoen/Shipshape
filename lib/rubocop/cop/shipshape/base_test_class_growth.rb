# frozen_string_literal: true

require "rubocop/cop/shipshape/explains"

module RuboCop
  module Cop
    module Shipshape
      # Holds the ratchet half of `a-test-inherits-what-it-needs`: every definition a base test
      # class or support module holds, and its size in lines, both watched to only fall.
      #
      # `shipshape check` reads `qualifying_superclass?` off this class, so a base test class is
      # named once, here, not a second time in the code that sums its lines.
      class BaseTestClassGrowth < Base
        include Explains

        READERS = %i[attr_reader attr_accessor attr_writer].freeze
        LIFECYCLE = %i[setup teardown].freeze
        METHOD_MAKERS = %i[define_method alias_method delegate].freeze

        # A class qualifies by its superclass looking like a test's own; a module always
        # qualifies, since it has no superclass to read and is where `extend self` hides.
        TEST_BASE_SUPERCLASS = /Test(Case)?\z/.freeze

        def self.qualifying_superclass?(source)
          return false if source.nil?

          source.sub(/\A::/, "") =~ TEST_BASE_SUPERCLASS ? true : false
        end

        def on_class(node)
          return unless self.class.qualifying_superclass?(node.parent_class&.source)

          handle_body(node.body)
        end

        def on_module(node)
          handle_body(node.body)
        end

        private

        # `if`, a block or `class << self` may hide a definition; recursed into, never counted.
        def handle_body(body)
          return if body.nil?

          statements = body.begin_type? ? body.children : [body]
          statements.each { |statement| walk(statement) }
        end

        def walk(node)
          return if node.nil?

          kind = kind_of(node)
          return add_offense(node, message: message_for(node, kind)) if kind

          each_branch(node) { |branch| handle_body(branch) } if wrapper?(node)
        end

        def wrapper?(node)
          node.if_type? || node.block_type? || node.sclass_type?
        end

        def each_branch(node)
          if node.if_type?
            node.branches.each { |branch| yield branch }
          else
            yield node.body
          end
        end

        def kind_of(node)
          return "a method" if method?(node)
          return "a constant" if node.respond_to?(:casgn_type?) && node.casgn_type?
          return "a reader" if reader?(node)
          return "a setup or teardown block" if lifecycle?(node)
          return "a method" if method_maker?(node)

          nil
        end

        def method?(node)
          node.respond_to?(:def_type?) && (node.def_type? || node.defs_type?)
        end

        def reader?(node)
          send?(node) && node.receiver.nil? && READERS.include?(node.method_name)
        end

        def lifecycle?(node)
          candidate = send_within(node)

          send?(candidate) && candidate.receiver.nil? && LIFECYCLE.include?(candidate.method_name)
        end

        def method_maker?(node)
          candidate = send_within(node)

          send?(candidate) && candidate.receiver.nil? && METHOD_MAKERS.include?(candidate.method_name)
        end

        def send_within(node)
          node.respond_to?(:block_type?) && node.block_type? ? node.send_node : node
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
