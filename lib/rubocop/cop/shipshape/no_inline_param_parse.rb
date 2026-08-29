# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      # Holds the parsing half of `input-is-parsed-at-the-seam`.
      #
      # A parameter is a string somebody typed. Turning it into a Date or an Integer inline,
      # in an action, turns a typo into a 500 — the parsers bounce instead, with the reason.
      #
      # `to_i` and `to_f` are **not** here: they cannot raise, so they are silent coercion
      # and `Shipshape/NoSilentCoercion` holds them.
      #
      # WHAT IT DOES NOT CATCH: the method list is **closed**, so a parser it does not name
      # is uncovered. The parameter must be reached syntactically inside the call, so a local
      # assigned from `params` earlier is invisible. Views are not covered.
      #
      # @example
      #   # bad — a typo here is a 500, and the reason never reaches the requester
      #   Date.parse(params[:on])
      #   Integer(params[:id])
      #
      #   # good — one parser, at the edge, that bounces with the reason
      #   date_param!(:on, time_zone: time_zone_param!(:zone))
      #   integer_param!(:id)
      class NoInlineParamParse < Base
        include ReadsKinds
        extend AutoCorrector

        PARSERS = %i[parse parse! strptime iso8601 rfc3339 civil new].freeze
        CONVERSIONS = %i[Integer Float Rational Complex BigDecimal].freeze
        TYPES = %w[Date Time DateTime BigDecimal ActiveSupport::TimeZone].freeze

        def on_send(node)
          return unless one_of?(governed_kinds)
          return unless reads_params?(node)

          named = node.receiver ? node.receiver.source : node.method_name.to_s
          return unless parser?(node) || conversion?(node)

          add_offense(node, message: message_for(node.source, suggestion_for(named))) do |corrector|
            replacement = correction_for(node)
            corrector.replace(node, replacement) if replacement
          end
        end

        private

        def parser?(node)
          PARSERS.include?(node.method_name) &&
            node.receiver && TYPES.include?(node.receiver.source.sub(/\A::/, ""))
        end

        # `Integer(params[:id])` parses as a receiverless send.
        def conversion?(node)
          node.receiver.nil? && CONVERSIONS.include?(node.method_name)
        end

        # **The date and time parsers are never corrected**, because their replacement takes a
        # zone — `date_param!(:on, time_zone: ...)` — and which zone is a decision the source
        # does not contain. `a-time-names-its-zone` says a zone nobody stated is a fact nobody
        # declared, so inventing one here would be the cop writing the defect it forbids.
        CORRECTABLE = {
          Integer: "integer_param!",
          Float: "decimal_param!",
          BigDecimal: "decimal_param!",
          Rational: "decimal_param!",
        }.freeze

        def correction_for(node)
          return unless node.receiver.nil?

          parser = CORRECTABLE[node.method_name]
          return unless parser

          argument = node.arguments.first
          return unless argument.respond_to?(:send_type?) && argument.send_type?
          return unless %i[[] fetch].include?(argument.method_name)

          key = argument.arguments.first
          return unless key.respond_to?(:type) && %i[sym str].include?(key.type)

          "#{parser}(#{key.value.to_sym.inspect})"
        end

        # The example names the parser for the type actually being parsed. A generic one
        # would be a rule restated rather than an answer, and the reader would still have to
        # go and find which parser applies.
        def suggestion_for(named)
          case named
          when "Date" then "date_param!(:on, time_zone: time_zone_param!(:zone))"
          when "BigDecimal" then "decimal_param!(:amount)"
          when "ActiveSupport::TimeZone" then "time_zone_param!(:zone)"
          when "Integer", "Rational", "Complex" then "integer_param!(:id)"
          when "Float" then "decimal_param!(:amount)"
          else "time_param!(:at, time_zone: time_zone_param!(:zone))"
          end
        end

        def message_for(source, suggestion)
          explain(
            "`#{source}` parses a request parameter inline.",
            because: "A parameter is a string somebody typed, so this raises on a typo — " \
                     "and an exception here is a 500 the requester cannot act on, instead " \
                     "of a bounce that says which field was wrong. Parsed in one place, " \
                     "at the edge, it is also parsed once: everything past the seam is " \
                     "handed a real value and never wonders.",
            instead: <<~RUBY,
              # in the action — the bang form bounces with the reason, the plain form
              # takes the default you name
              value = #{suggestion}

              # past the seam nothing re-parses, because it was handed the real thing
              SettleInvoice.call(settled_on: value)
            RUBY
          )
        end

        # `params[:id]`, `params.fetch(:id)`, `params.require(:booking)` — anywhere inside
        # this call, at any depth.
        def reads_params?(node)
          node.each_descendant(:send).any? { |inner| inner.method_name == :params && inner.receiver.nil? }
        end

        def governed_kinds
          cop_config.fetch("Kinds", %w[request_handling entry_point])
        end
      end
    end
  end
end
