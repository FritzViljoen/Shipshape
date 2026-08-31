# frozen_string_literal: true

require "rubocop/cop/shipshape/explains"

module RuboCop
  module Cop
    module Shipshape
      # Holds the half of `a-permission-is-the-class-name` that the base classes cannot hold
      # themselves.
      class EveryDoorChecksPermission < Base
        include Explains

        DOORS = %w[
          command io_command legacy_command query io_query legacy_query workflow
        ].freeze

        CHECK = :permits?

        def on_new_investigation
          return unless door?
          return unless authorisation_installed?
          return if checks_permission?

          add_offense(range, message: message_for(File.basename(processed_source.file_path)))
        end

        private

        def door?
          DOORS.include?(File.basename(processed_source.file_path, ".rb"))
        end

        # The module the installer writes only when asked for authorisation. Its absence
        # means this application did not opt in, and there is nothing to keep.
        def authorisation_installed?
          File.exist?(File.join(File.dirname(processed_source.file_path), "permission.rb"))
        end

        def checks_permission?
          processed_source.ast&.each_node(:send)&.any? { |node| node.method_name == CHECK }
        end

        def range
          processed_source.ast&.source_range || processed_source.buffer.source_range
        end

        def message_for(file)
          explain(
            "`#{file}` is a door and no longer checks a permission.",
            because: "`shipshape install` never overwrites your files, which is the right " \
                     "contract and leaves this hole: the guard was the shape of the " \
                     "generated code, so removing one line here disables authorisation for " \
                     "every operation of this kind, in every controller and job, and " \
                     "nothing else anywhere fails. There is no test in your application " \
                     "that would go red.",
            instead: <<~RUBY,
              # in app/shipshape/#{File.basename(file)}
              extend Permission

              def self.call(actor: nil, **arguments)
                return Result.failure(:forbidden) unless permits?(actor)

                operation = anonymous? ? new(**arguments) : new(actor: actor, **arguments)
                # ... the work
              end

              # A query has no envelope, so it raises instead:
              #   raise Permission::Refused, permission unless permits?(actor)
              #
              # Deliberately unauthenticated? The operation says so by implementing
              # `anonymous_call` — never by the door skipping the check.
            RUBY
          )
        end
      end
    end
  end
end
