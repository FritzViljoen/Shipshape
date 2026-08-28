# frozen_string_literal: true

module Shipshape
  module Measures
    # Who inherits from whom, across the whole repository, built once.
    #
    # **A base class is not a stray object, and this is how the report knows which is which
    # without a list.** A class is a base class if something else in this repository
    # inherits from it — derived from the code, so it cannot go stale and no application has
    # to declare anything.
    module Inheritance
      module_function

      # { "SettleInvoice" => "Command", "Command" => nil, ... } for every standalone class.
      def map(sources)
        sources.each_with_object({}) do |source, found|
          ClassReading.classes(source).each do |node|
            next if ClassReading.owned_by_a_class?(source.ast, node)

            found[ClassReading.name_of(node)] = ClassReading.superclass_of(node)
          end
        end
      end

      # Every name something inherits from — the base classes, whatever they are called.
      def bases(sources)
        map(sources).values.compact.map { |name| name.split("::").last }.to_set
      end

      def base?(sources_map, node_name)
        sources_map.include?(node_name.split("::").last)
      end
    end
  end
end
