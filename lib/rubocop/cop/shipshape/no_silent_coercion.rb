# frozen_string_literal: true

require "rubocop/cop/shipshape/explains"

module RuboCop
  module Cop
    module Shipshape
      # Holds the cast half of `no-silent-coercion`.
      #
      # `"1abc".to_i` is `1`. `"banana".to_i` is `0`. `nil.to_s` is `""`. None raises, so
      # rubbish becomes a plausible value and the request is answered with something nobody
      # asked for.
      #
      # WHAT IT DOES NOT CATCH: a cast on a value already asserted as the right type is
      # harmless and **syntactically identical** to the forbidden one. So the cop covers only
      # the same-expression traceable case — the cast is applied directly to something read
      # from request parameters — and **misses every value that passed through a local
      # first**. That is a deliberate trade: the alternative fires on correct code.
      #
      # @example
      #   # bad — "banana".to_i is 0, and page 0 is a real page
      #   params[:page].to_i
      #
      #   # good — it bounces, with the reason, naming the field
      #   integer_param!(:page)
      #
      #   # good — a default you chose, rather than one the cast invented
      #   integer_param(:page, default: 1)
      class NoSilentCoercion < Base
        include Explains

        CASTS = {
          to_i: "integer_param!(:page)",
          to_f: "decimal_param!(:amount)",
          to_r: "decimal_param!(:amount)",
          to_c: "decimal_param!(:amount)",
          to_d: "decimal_param!(:amount)",
          to_s: "text_param!(:name)",
          to_a: "enum_param!(:state, %w[held sold])",
        }.freeze

        # `nil.to_s` is `""` and `nil.to_a` is `[]`, so absence becomes a present-looking
        # value. The numeric casts invent a number; these invent a *shape*, which is worse,
        # because nothing downstream can tell an empty answer from an absent one.
        SHAPES = %i[to_s to_a].freeze

        UNTRUSTED = %i[params request env session cookies].freeze

        def on_send(node)
          suggestion = CASTS[node.method_name]
          return unless suggestion
          return unless untrusted?(node.receiver)

          add_offense(node, message: message_for(node.source, node.method_name, suggestion))
        end

        private

        # Traceable in the same expression: `params[:page].to_i`. A value that passed
        # through a local is not covered, and the law says so.
        def untrusted?(receiver)
          return false unless receiver

          receiver.each_node(:send).any? { |inner| source?(inner) } || source?(receiver)
        end

        def source?(node)
          node.send_type? && node.receiver.nil? && UNTRUSTED.include?(node.method_name)
        end

        def harm_of(cast)
          if SHAPES.include?(cast)
            "`nil.#{cast}` is empty rather than missing, so absence arrives downstream " \
              "wearing the shape of a real answer"
          else
            "`\"banana\".#{cast}` is 0 and `\"1abc\".#{cast}` is 1"
          end
        end

        def message_for(source, cast, suggestion)
          explain(
            "`#{source}` turns whatever arrived into a number that cannot fail.",
            because: "#{harm_of(cast)} — no exception, " \
                     "no log line, no failing test. The request was wrong and the answer " \
                     "looked right, so the defect is found by a customer rather than by " \
                     "the build. An operation completes, or it says why it did not; what " \
                     "it may never do is answer.",
            instead: <<~RUBY,
              # bounces with the reason, naming the field that was wrong
              #{suggestion}

              # or a default you chose, rather than one the cast invented for you
              integer_param(:page, default: 1)
            RUBY
          )
        end
      end
    end
  end
end
