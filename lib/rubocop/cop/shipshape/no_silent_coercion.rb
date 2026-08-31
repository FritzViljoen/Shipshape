# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      # Holds the cast half of `no-silent-coercion`.
      class NoSilentCoercion < Base
        include ReadsKinds
        extend AutoCorrector

        # A correction is only ever emitted for `params`. Rewriting a `session` read moves it to
        # the query string: over lobsters that turned an OAuth state check into
        # `text_param!(:state) != text_param!(:github_state)`, comparing a parameter to itself.
        CORRECTABLE_SOURCE = "params"

        # Not behaviour-preserving, hence `SafeAutoCorrect: false`: `"banana".to_i` is 0 today
        # and a bounce afterwards. Only a literal key is rewritten.
        PARSERS = {
          to_i: "integer_param!",
          to_f: "decimal_param!",
          to_r: "decimal_param!",
          to_c: "decimal_param!",
          to_d: "decimal_param!",
          to_s: "text_param!",
        }.freeze

        CASTS = {
          to_i: "integer_param!(:page)",
          to_f: "decimal_param!(:amount)",
          to_r: "decimal_param!(:amount)",
          to_c: "decimal_param!(:amount)",
          to_d: "decimal_param!(:amount)",
          to_s: "text_param!(:name)",
          to_a: "enum_param!(:state, %w[held sold])",
        }.freeze

        SHAPES = %i[to_s to_a].freeze

        UNTRUSTED = %i[params request env session cookies].freeze

        def on_send(node)
          suggestion = CASTS[node.method_name]
          return unless suggestion
          return unless untrusted?(node.receiver)
          # Only when applied directly: scanning the whole receiver made
          # `url_for(params.permit(:q)).to_s` an offence.
          return if SHAPES.include?(node.method_name) && !reads_a_parameter?(node.receiver)

          add_offense(node, message: message_for(node.source, node.method_name, suggestion)) do |corrector|
            replacement = correction_for(node)
            corrector.replace(node, replacement) if replacement
          end
        end

        private

        def untrusted?(receiver)
          return false unless receiver

          receiver.each_node(:send).any? { |inner| source?(inner) } || source?(receiver)
        end

        def reads_a_parameter?(node)
          return false unless node.respond_to?(:send_type?) && node.send_type?
          return false unless %i[[] fetch require dig].include?(node.method_name)

          source?(node.receiver)
        end

        def source?(node)
          node.respond_to?(:send_type?) && node.send_type? && node.receiver.nil? &&
            UNTRUSTED.include?(node.method_name)
        end

        def correction_for(node)
          parser = PARSERS[node.method_name]
          return unless parser
          # `integer_param!` is wired into ApplicationController and nowhere else.
          return unless one_of?(door_kinds)

          key = literal_key(node.receiver)
          return unless key

          "#{parser}(#{key})"
        end

        # Whole and unchained: `fetch(:page, "7")` carries a default the rewrite would delete.
        def literal_key(receiver)
          return unless receiver.respond_to?(:send_type?) && receiver.send_type?
          return unless %i[[] fetch].include?(receiver.method_name)
          return unless receiver.arguments.length == 1
          return unless receiver.receiver&.source == CORRECTABLE_SOURCE

          argument = receiver.arguments.first
          return unless argument.respond_to?(:type) && %i[sym str].include?(argument.type)

          argument.value.to_sym.inspect
        end

        def door_kinds
          cop_config.fetch("Kinds", %w[request_handling entry_point])
        end

        def produced(cast)
          SHAPES.include?(cast) ? "a value" : "a number"
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
            "`#{source}` turns whatever arrived into #{produced(cast)} that cannot fail.",
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
