# frozen_string_literal: true

module Shipshape
  module Measures
    # One thing found, somewhere: a count with no examples is an accusation. `context` carries
    # whatever the measure needs to propose a better shape later, and most need none.
    Finding = Struct.new(:relative, :line, :label, :context, keyword_init: true) do
      def to_s
        "#{relative}:#{line}  #{label}"
      end
    end

    # Not a base class the measures inherit: `one-level-of-inheritance` binds this gem too.
    module ClassReading
      module_function

      def classes(source)
        found = []
        walk(source.ast) { |node| found << node if node.class_type? }
        found
      end

      def enclosing_method(root, target)
        found = nil
        walk(root) do |node|
          next unless node.def_type?
          next unless node.loc.expression.begin_pos <= target.loc.expression.begin_pos &&
                      node.loc.expression.end_pos >= target.loc.expression.end_pos

          found = node.method_name
        end
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

      # Reachable name, not the bare one: reading `ProductCode` off a nested class turns an
      # inner class into what looks like a stray object.
      def qualified_name(root, class_node)
        enclosing = []
        walk(root) do |node|
          next unless %i[class module].include?(node.type)
          next if node.equal?(class_node)
          next unless contains?(node, class_node)

          enclosing << node.children.first.source
        end

        (enclosing + [name_of(class_node)]).join("::")
      end

      # Nested in a class means owned; nested only in modules means namespaced.
      def owned_by_a_class?(root, class_node)
        found = false
        walk(root) do |node|
          next unless node.class_type?
          next if node.equal?(class_node)

          found = true if contains?(node, class_node)
        end
        found
      end

      def contains?(outer, inner)
        outer.loc.expression.begin_pos < inner.loc.expression.begin_pos &&
          outer.loc.expression.end_pos >= inner.loc.expression.end_pos
      end

      def superclass_of(class_node)
        class_node.children[1] && class_node.children[1].source
      end

      def public_methods_of(class_node)
        body = class_node.body
        return [] if body.nil?

        statements = body.begin_type? ? body.children : [body]
        visible(statements).reject { |node| ALWAYS_PRIVATE.include?(node.method_name) }
      end

      ALWAYS_PRIVATE = %i[initialize initialize_copy respond_to_missing? to_s inspect ==
                          eql? hash].freeze

      # Bare `private` switches; `private :name` marks one. Nothing here is a Ruby parser.
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
