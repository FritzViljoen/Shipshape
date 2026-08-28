# frozen_string_literal: true

require "shipshape/measures/finding"

module Shipshape
  module Measures
    # A request parameter cast or parsed where it is used, rather than at a seam.
    #
    # `params[:id].to_i` is `1` for `"1abc"`, and `find` on it serves record 1 while nothing
    # anywhere fails. `Date.parse(params[:on])` turns a typo into a 500. Each of these is a
    # place where a string somebody typed became a value nobody checked.
    #
    # Counted anywhere, not only in controllers: a parameter that has reached a model or a
    # service unparsed is the same defect, further from the door.
    class InputParsedInTheAction
      TITLE = "Request input cast where it is used"
      LAW = "input-is-parsed-at-the-seam"
      WHY = "`params[:id].to_i` is 1 for \"1abc\", and the lookup then serves record 1 " \
            "while nothing anywhere fails."

      NOUN = "reads of a parameter"

      def population(sources)
        sources.sum do |source|
          count = 0
          ClassReading.walk(source.ast) { |node| count += 1 if param_read?(node) }
          count
        end
      end

      CASTS = %i[to_i to_f to_d to_date to_datetime to_time in_time_zone parse strptime iso8601].freeze

      def call(sources)
        sources.flat_map do |source|
          casts(source).map do |node|
            Finding.new(relative: source.relative, line: node.loc.line, label: node.method_name.to_s)
          end
        end
      end

      private

      def casts(source)
        found = []
        ClassReading.walk(source.ast) do |node|
          next unless node.send_type? && CASTS.include?(node.method_name)

          found << node if param_read?(node.receiver) || param_read?(node.arguments.first)
        end
        found
      end

      ACCESS = %i[[] fetch dig require permit].freeze

      # One read of a parameter: `params[:x]`, `params.fetch(:x)`, `params.dig(...)`, or the
      # same through a `*_params` helper.
      #
      # AN EARLIER VERSION MATCHED THE NODE'S SOURCE TEXT for the word `params`, which meant
      # every expression enclosing a parameter read counted as another read — the denominator
      # came out at 8,311 on an application with a few hundred, and the share it produced was
      # meaningless. Structure, not text.
      def param_read?(node)
        return false unless node.is_a?(RuboCop::AST::Node) && node.send_type?
        return false unless ACCESS.include?(node.method_name)

        params?(node.receiver)
      end

      # `params`, or a `*_params` helper — both are a bare method call with no receiver.
      def params?(node)
        return false unless node.is_a?(RuboCop::AST::Node) && node.send_type?
        return false unless node.receiver.nil? && node.arguments.empty?

        node.method_name == :params || node.method_name.to_s.end_with?("_params")
      end
    end
  end
end
