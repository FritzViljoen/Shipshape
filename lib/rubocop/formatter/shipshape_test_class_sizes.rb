# frozen_string_literal: true

require "json"
require "rubocop/cop/shipshape/base_test_class_growth"

module RuboCop
  module Formatter
    # `Shipshape/BaseTestClassGrowth`'s own recorded spans, read back once its run ends.
    class ShipshapeTestClassSizes < BaseFormatter
      def started(_target_files)
        Cop::Shipshape::BaseTestClassGrowth.reset_spans!
      end

      def finished(_inspected_files)
        output.write(JSON.dump(Cop::Shipshape::BaseTestClassGrowth.merged_sizes))
      end
    end
  end
end
