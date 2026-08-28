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

          found << node if touches_params?(node.receiver) || touches_params?(node.arguments.first)
        end
        found
      end

      # `params[:x]`, `params.fetch(:x)`, and one level of helper such as `person_params[:x]`.
      # A parameter assigned to a local first is invisible, which is stated rather than
      # quietly hoped about.
      def touches_params?(node)
        return false unless node.is_a?(RuboCop::AST::Node)

        source = node.source
        source.include?("params[") || source.include?("params.fetch") || source =~ /\bparams\b/ ? true : false
      end
    end
  end
end
