# frozen_string_literal: true

require "rubocop/cop/shipshape/explains"

module RuboCop
  module Cop
    module Shipshape
      # Holds `every-operation-reports-what-it-did` over the **installed** base classes.
      #
      # The generated base classes record every attempt, and this gem's own suite proves each
      # of them does. That proof covers the templates. **It covers nothing once they are
      # installed**, because a generated file is the application's to edit — and a base class
      # that quietly lost its audit call disables the trail for every operation of that kind
      # while nothing else fails. Exactly the gap `Shipshape/EveryDoorChecksPermission` exists
      # to close for the permission check, and this is its sibling.
      #
      # **A query is not here.** A read is not an attempt to change anything, and recording
      # every read is how an audit log becomes a log.
      #
      # WHAT IT DOES NOT CATCH: it looks for the message `AuditLog.record` anywhere in the
      # file, so an application that renamed the recorder, or wrapped it, reads as missing —
      # a false positive to be argued rather than suppressed. It cannot tell an entry that is
      # written from one that is written *correctly*, or that the call is on a path that runs.
      # It says nothing about an operation that reaches the database without going through a
      # base class at all.
      #
      # @example
      #   # bad — app/shipshape/command.rb with the line deleted
      #   def self.call(**arguments)
      #     result = ActiveRecord::Base.transaction { new(**arguments).__perform__ }
      #     result
      #   end
      #
      #   # good
      #   AuditLog.record(operation: name, outcome: result.success? ? :succeeded : :failed,
      #                   error: result.error)
      class OperationsReportWhatTheyDid < Base
        include Explains

        # The operations that write. A query answers a caller and changes nothing.
        WRITING = %w[command io_command legacy_command workflow].freeze

        RECORDER = "AuditLog"

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
            instead: <<~RUBY,
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
