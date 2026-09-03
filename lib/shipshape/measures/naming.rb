# frozen_string_literal: true

module Shipshape
  module Measures
    # Names a proposed operation after the work it would take over.
    module Naming
      module_function

      VERBS = {
        index: "List", show: "Find", new: "Build", edit: "Find",
        create: "Create", update: "Update", destroy: "Remove"
      }.freeze

      READS = %i[index show new edit].freeze

      # A known action becomes verb + noun; anything else keeps its own name, because
      # appending the subject produced `FindUserFromRssTokenUser`.
      def operation_for(action:, subject:)
        return nil if action.nil?

        verb = VERBS[action.to_sym]
        return camel(action.to_s) if verb.nil?

        "#{verb}#{action.to_sym == :index ? plural(subject) : subject}"
      end

      # The message is better evidence than the action name: an action outside Rails' seven
      # says nothing about direction, and guessing Command from silence gets laughed at.
      WRITES = %i[create create! update update! destroy destroy_all delete delete_all save
                  save! insert insert_all upsert upsert_all increment! decrement! touch].freeze

      INSTANCE_WRITES = %i[save save! update update! update_attribute update_attributes
                           update_column update_columns destroy destroy! delete touch
                           increment! decrement! toggle! assign_attributes reload
                           insert append push concat].freeze

      def writes?(body)
        return false unless body.is_a?(RuboCop::AST::Node)

        found = false
        walk(body) do |node|
          next unless node.send_type?

          found = true if WRITES.include?(node.method_name) || INSTANCE_WRITES.include?(node.method_name)
          found = true if node.method_name.to_s.end_with?("=") && node.receiver&.self_type?
        end
        found
      end

      def walk(node, &block)
        return unless node.is_a?(RuboCop::AST::Node)

        block.call(node)
        node.children.each { |child| walk(child, &block) }
      end

      def first_write_in(body)
        return nil unless body.is_a?(RuboCop::AST::Node)

        found = nil
        walk(body) do |node|
          next unless node.send_type? && found.nil?

          found = node.method_name if WRITES.include?(node.method_name) || INSTANCE_WRITES.include?(node.method_name)
        end
        found
      end

      def kind_for(action, message: nil)
        return "Command" if message && WRITES.include?(message.to_sym)
        return "Query" if message

        READS.include?(action.to_sym) ? "Query" : "Command"
      end

      def path_for(name, kind)
        directory = kind == "Query" ? "queries" : "commands"

        "app/#{directory}/#{snake(name)}.rb"
      end

      def camel(word)
        word.split("_").map { |part| part.sub(/\A./, &:upcase) }.join
      end

      def snake(name)
        name.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
      end

      # Crude on purpose: an irregular plural gets a wrong name in a sketch meant to be edited.
      def plural(word)
        return "#{word[0..-2]}ies" if word.end_with?("y")
        return "#{word}es" if word.end_with?("s", "x", "ch", "sh")

        "#{word}s"
      end
    end
  end
end
