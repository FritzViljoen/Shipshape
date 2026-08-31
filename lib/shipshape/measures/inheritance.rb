# frozen_string_literal: true

module Shipshape
  module Measures
    # Who inherits from whom, across the whole repository, built once.
    module Inheritance
      module_function

      # Nested ones included: skipping them made an inner error base read as accreted behaviour.
      def map(sources)
        sources.each_with_object({}) do |source, found|
          ClassReading.classes(source).each do |node|
            found[ClassReading.name_of(node)] = ClassReading.superclass_of(node)
          end
        end
      end

      def bases(sources)
        map(sources).values.compact.map { |name| name.split("::").last }.to_set
      end

      def base?(sources_map, node_name)
        sources_map.include?(node_name.split("::").last)
      end
    end
  end
end
