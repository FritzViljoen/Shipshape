# frozen_string_literal: true

require "shipshape/measures/finding"

module Shipshape
  module Measures
    # Controllers naming a constant that is a model.
    #
    # This is the single most useful number in the report, because it is the one that says
    # how far the application is from having a domain at all. Every one of these is a place
    # where a rule could live but does not, and where an agent editing the controller has to
    # understand the schema to change anything.
    #
    # Models are found by their own file names — `app/models/person.rb` means `Person` — so
    # no configuration is needed and no application has to be believed about its own layout.
    class RequestHandlingThatReachesPersistence
      TITLE = "Request handling reaching straight into persistence"
      LAW = "the-call-graph-is-declared"
      WHY = "Each of these is a place where a rule could live and does not, and where " \
            "changing the controller means understanding the schema."

      def call(sources)
        models = model_names(sources)

        controllers(sources).flat_map do |source|
          constants_in(source).select { |node| models.include?(node.source.split("::").last) }.map do |node|
            Finding.new(relative: source.relative, line: node.loc.line, label: node.source)
          end
        end
      end

      private

      def controllers(sources)
        sources.select { |source| source.relative.split("/")[1] == "controllers" }
      end

      # `app/models/order/line.rb` is `Order::Line`; the last segment is what a controller
      # writes, so that is what is matched.
      def model_names(sources)
        sources.select { |source| source.relative.start_with?("app/models/") }.map do |source|
          File.basename(source.relative, ".rb").split("_").map(&:capitalize).join
        end.to_set
      end

      def constants_in(source)
        found = []
        ClassReading.walk(source.ast) do |node|
          found << node.receiver if node.send_type? && node.receiver && node.receiver.const_type?
        end
        found
      end
    end
  end
end
