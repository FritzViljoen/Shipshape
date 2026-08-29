# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"

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
        include ReadsKinds
        extend AutoCorrector

        # **A correction is only ever emitted for `params`.** `session`, `cookies`, `env` and
        # `request` are reported — they are untrusted in the sense the law means — but
        # rewriting one to `text_param!` moves the read from the session to the query string.
        # That is not a refactor, it is a vulnerability: over lobsters this turned an OAuth
        # state check into `text_param!(:state) != text_param!(:github_state)`, comparing a
        # parameter to itself, and put the 2FA re-authentication window under the requester's
        # control. Found by running the correction over real code.
        CORRECTABLE_SOURCE = "params"

        # **The correction is deliberately not behaviour-preserving**, which is why this cop
        # is `SafeAutoCorrect: false` and the fix arrives under `-A` rather than `-a`.
        # `"banana".to_i` is 0 today and a bounce afterwards — that IS the rule, and applying
        # it silently to a running application would be the same sin the cop is named for.
        #
        # Only a literal key is rewritten: `params[key].to_i` names a parameter this cannot
        # read, so it is reported and left alone.
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

        # `nil.to_s` is `""` and `nil.to_a` is `[]`, so absence becomes a present-looking
        # value. The numeric casts invent a number; these invent a *shape*, which is worse,
        # because nothing downstream can tell an empty answer from an absent one.
        SHAPES = %i[to_s to_a].freeze

        UNTRUSTED = %i[params request env session cookies].freeze

        def on_send(node)
          suggestion = CASTS[node.method_name]
          return unless suggestion
          return unless untrusted?(node.receiver)
          # A shape cast is only a coercion when applied DIRECTLY to the parameter.
          # `url_for(params.permit(:q)).to_s` is a String being made a String, and scanning
          # the whole receiver for a `params` anywhere inside made that an offence.
          return if SHAPES.include?(node.method_name) && !reads_a_parameter?(node.receiver)

          add_offense(node, message: message_for(node.source, node.method_name, suggestion)) do |corrector|
            replacement = correction_for(node)
            corrector.replace(node, replacement) if replacement
          end
        end

        private

        # Traceable in the same expression: `params[:page].to_i`. A value that passed
        # through a local is not covered, and the law says so.
        def untrusted?(receiver)
          return false unless receiver

          receiver.each_node(:send).any? { |inner| source?(inner) } || source?(receiver)
        end

        # `params[:name]`, `session.fetch(:x)` — the read itself, not any expression that
        # happens to contain one.
        def reads_a_parameter?(node)
          return false unless node.respond_to?(:send_type?) && node.send_type?
          return false unless %i[[] fetch require dig].include?(node.method_name)

          source?(node.receiver)
        end

        def source?(node)
          node.respond_to?(:send_type?) && node.send_type? && node.receiver.nil? &&
            UNTRUSTED.include?(node.method_name)
        end

        # `params[:page].to_i` → `integer_param!(:page)`.
        def correction_for(node)
          parser = PARSERS[node.method_name]
          return unless parser
          # `integer_param!` comes from the TypedParams concern, which the installer wires
          # into ApplicationController and nowhere else. Correcting a plain object that
          # happens to expose `params` emits a call to a method that does not exist there.
          return unless one_of?(door_kinds)

          key = literal_key(node.receiver)
          return unless key

          "#{parser}(#{key})"
        end

        # The read must be `params[:literal]`, whole and unchained. A nested read names a
        # different parameter than its inner key; `fetch(:page, "7")` carries a default the
        # author chose and the rewrite would delete.
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
