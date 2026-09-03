# frozen_string_literal: true

require "rubocop/cop/shipshape/explains"

module RuboCop
  module Cop
    module Shipshape
      # Holds `every-operation-reports-what-it-did` over the **installed** base classes.
      class OperationsReportWhatTheyDid < Base
        include Explains

        # The operations that write. A query answers a caller and changes nothing.
        # A workflow is not here: it performs no act, so it has nothing of its own to record.
        WRITING = %w[command io_command legacy_command].freeze

        RECORDER = "AuditLog"

        RECORDED = <<~RUBY
          # after the work, before answering
          AuditLog.record(
            operation: name,
            outcome: result.success? ? :succeeded : :failed,
            error: result.error,
          )

          # and the refusal, before returning it — that is the entry somebody comes
          # looking for
          AuditLog.record(operation: name, outcome: :refused, actor: actor, error: :forbidden)
        RUBY

        def on_new_investigation
          return unless writing_operation?
          return unless audit_log_installed?
          return if records?

          add_offense(range, message: message_for(File.basename(processed_source.file_path)))
        end

        private

        def writing_operation?
          writing.include?(File.basename(processed_source.file_path, ".rb"))
        end

        # The module the installer writes beside these. Its absence means this application has
        # no audit log to keep, so there is nothing to hold it to.
        def audit_log_installed?
          File.exist?(File.join(File.dirname(processed_source.file_path), "audit_log.rb"))
        end

        def records?
          processed_source.ast&.each_node(:send)&.any? do |node|
            node.receiver&.const_type? && node.receiver.source == recorder
          end
        end

        def range
          processed_source.ast&.source_range || processed_source.buffer.source_range
        end

        def message_for(file)
          explain(
            "`#{file}` no longer reports what it did.",
            because: "This base class is every operation of its kind. One that lost its " \
                     "audit call leaves no trace of anything those operations attempted — " \
                     "including the refusals, which are the entries nobody has when they " \
                     "need them — and nothing else fails, so the trail is empty and the " \
                     "build is green. The gem's own suite proves the template records; once " \
                     "installed, the file is yours, and this is what notices.",
            instead: RECORDED,
          )
        end

        def writing
          @writing ||= cop_config.fetch("Operations", WRITING)
        end

        def recorder
          @recorder ||= cop_config.fetch("Recorder", RECORDER)
        end
      end
    end
  end
end
