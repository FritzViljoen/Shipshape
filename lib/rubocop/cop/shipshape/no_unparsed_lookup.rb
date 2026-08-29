# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      # Holds the lookup half of `input-is-parsed-at-the-seam`.
      #
      # **`find(params[:id])` works, which is the trap.** The adapter coerces the string, so
      # `/people/1abc` serves person 1 and nothing anywhere fails. There is no exception to
      # find, no log line, and no test that fails — the request was wrong and the answer
      # looked right.
      #
      # WHAT IT DOES NOT CATCH: the finder list is **closed**, so a finder it does not name
      # is uncovered. The parameter must be reached syntactically inside the call, so a local
      # assigned from `params` earlier is invisible. Views are not covered.
      #
      # @example
      #   # bad — /people/1abc serves person 1, silently
      #   PersonRecord.find(params[:id])
      #   BookingRecord.where(state: params[:state])
      #
      #   # good — parsed once, at the edge, and refused if it is not what it claims
      #   PersonRecord.find(integer_param!(:id))
      #   BookingRecord.where(state: enum_param!(:state, %w[held sold]))
      class NoUnparsedLookup < Base
        include ReadsKinds
        extend AutoCorrector

        FINDERS = %i[find find_by find_by! where find_or_create_by find_or_initialize_by
                     exists? update update! create create! new destroy delete
                     insert insert_all upsert first_or_create].freeze

        def on_send(node)
          return unless FINDERS.include?(node.method_name)
          return unless one_of?(governed_kinds)

          node.arguments.each do |argument|
            reads = param_reads(argument)
            reads.each do |read|
              add_offense(read, message: message_for(read.source, node.method_name)) do |corrector|
                replacement = correction_for(read)
                corrector.replace(read, replacement) if replacement
              end
            end
          end
        end

        private

        # In an argument, in a hash value, nested any depth down.
        def param_reads(argument)
          found = []
          found << argument if params_read?(argument)
          argument.each_descendant(:send) { |inner| found << inner if params_read?(inner) }
          found
        end

        def params_read?(node)
          return false unless node.send_type?
          return false unless %i[[] fetch require permit dig].include?(node.method_name)

          receiver = node.receiver
          receiver&.send_type? && receiver.method_name == :params && receiver.receiver.nil?
        end

        # **Only `find(params[:id])` is corrected**, and only positionally: that is the
        # primary key, and Rails makes it an integer.
        #
        # Nothing else is safe, because **the parser cannot be derived from a name**. This
        # was found by running the correction over lobsters, where
        # `where(short_id: params[:story_id])` was rewritten to `integer_param!` — `short_id`
        # is base 36, and the correction would have broken every one of those lookups. A
        # `_id` suffix says nothing about the type; only the column does, and the column is
        # not in the source. Everything else is reported and left for a person, because
        # replacing a silent wrong answer with a confident one is worse than the offence.
        def correction_for(read)
          return unless positional_find?(read)

          argument = read.arguments.first
          return unless argument.respond_to?(:type) && %i[sym str].include?(argument.type)
          return unless argument.value.to_s == "id"

          "integer_param!(:id)"
        end

        def positional_find?(read)
          parent = read.parent
          return false unless parent.respond_to?(:send_type?) && parent.send_type?

          %i[find find!].include?(parent.method_name) && parent.arguments.first.equal?(read)
        end

        def message_for(source, finder)
          explain(
            "`#{source}` reaches `#{finder}` unparsed.",
            because: "This works, which is the trap. The adapter coerces the string, so " \
                     "`1abc` finds row 1 and nothing anywhere fails — no exception, no log " \
                     "line, no failing test. The request was wrong and the answer looked " \
                     "right, which is the one failure mode that survives to production.",
            instead: <<~RUBY,
              # parsed once, at the edge, and refused if it is not what it claims to be
              PersonRecord.find(integer_param!(:id))
              BookingRecord.where(state: enum_param!(:state, %w[held sold]))
            RUBY
          )
        end

        def governed_kinds
          cop_config.fetch("Kinds", %w[request_handling entry_point])
        end
      end
    end
  end
end
