# frozen_string_literal: true

require "shipshape/settings"
require "shipshape/kinds"
require "rubocop/cop/shipshape/explains"

module RuboCop
  module Cop
    module Shipshape
      # What every cop here needs: which kind the file under inspection is.
      module ReadsKinds
        include Explains

        # Memoised against the file, not the cop: driving one instance over two files, which
        # RuboCop's API allows, let the first non-nil kind decide every file after it.
        def kind_of_inspected_file
          path = processed_source.file_path
          return @kind_of_inspected_file if defined?(@kind_memo_for) && @kind_memo_for == path

          @kind_memo_for = path
          @kind_of_inspected_file = kinds.for_path(path)
        end

        def one_of?(*wanted)
          wanted.flatten.include?(kind_of_inspected_file)
        end

        def kinds
          @kinds ||= ::Shipshape::Kinds.new(settings: settings, base_dir: base_dir)
        end

        def settings
          @settings ||= ::Shipshape::Settings.layout(config)
        end

        def base_dir
          config.base_dir_for_path_parameters
        end
      end
    end
  end
end
