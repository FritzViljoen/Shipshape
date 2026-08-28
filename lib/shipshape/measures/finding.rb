# frozen_string_literal: true

module Shipshape
  module Measures
    # One thing found, somewhere. A count with no examples is an accusation; a count with
    # three file:line references is a conversation.
    Finding = Struct.new(:relative, :line, :label, keyword_init: true) do
      def to_s
        "#{relative}:#{line}  #{label}"
      end
    end

    # Shared reading of a class body. Deliberately not a base class the measures inherit —
    # `one-level-of-inheritance` is a rule this gem asks of its consumers, and a tower of
    # measure subclasses would be the first thing a reader noticed it breaking.
    module ClassReading
      module_function

      def classes(source)
        found = []
        walk(source.ast) { |node| found << node if node.class_type? }
        found
      end

      def walk(node, &block)
        return unless node.is_a?(RuboCop::AST::Node)

        block.call(node)
        node.children.each { |child| walk(child, &block) }
      end

      def name_of(class_node)
        class_node.children.first.source
      end

      def superclass_of(class_node)
        class_node.children[1] && class_node.children[1].source
      end

      # Public instance methods, minus the ones the language or the framework asks for.
      def public_methods_of(class_node)
        body = class_node.body
        return [] if body.nil?

        statements = body.begin_type? ? body.children : [body]
        visible(statements).reject { |node| ALWAYS_PRIVATE.include?(node.method_name) }
      end

      ALWAYS_PRIVATE = %i[initialize initialize_copy respond_to_missing? to_s inspect ==
                          eql? hash].freeze

      # `private` with no arguments switches everything after it. `private :name` and
      # `private def name` mark one. Nothing else here pretends to be a Ruby parser.
      def visible(statements)
        public_defs = []
        private_from_here = false

        statements.each do |node|
          next unless node.is_a?(RuboCop::AST::Node)

          private_from_here = true if switch?(node)
          next if private_from_here
          next unless node.def_type?

          public_defs << node
        end
        public_defs
      end

      def switch?(node)
        node.send_type? && node.receiver.nil? &&
          %i[private protected].include?(node.method_name) && node.arguments.empty?
      end
    end
  end
end
