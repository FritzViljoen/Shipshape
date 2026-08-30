# frozen_string_literal: true

require "shipshape/settings"
require "shipshape/kinds"
require "rubocop/cop/shipshape/explains"

module RuboCop
  module Cop
    module Shipshape
      # What every cop here needs: which kind the file under inspection is.
      #
      # The layout is declared **once**, on `Shipshape/CallGraph`, and read from there.
      # Repeating `Kinds` on every cop would be a second copy of one fact, and the copy is
      # the one that goes stale.
      module ReadsKinds
        include Explains

        # **Memoised against the file, not against the cop.** A plain `||=` is correct only
        # because RuboCop happens to build a cop per file; drive one instance over two files
        # — which its own API lets you do — and the first non-nil kind decides every file
        # after it. Verified: a command inspected after a record was judged a record and
        # reported an offence it does not have. Keying on the path cannot go wrong whoever
        # does the driving, and needs no reset hook a cop can override.
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

        # Resolved from the configuration that loaded this cop, never from `Dir.pwd`: a cop
        # resolving paths from the working directory silently stops matching anything when
        # RuboCop runs from a subdirectory, and reports zero offences while doing it.
        def base_dir
          config.base_dir_for_path_parameters
        end
      end
    end
  end
end
