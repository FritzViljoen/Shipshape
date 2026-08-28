# frozen_string_literal: true

require "shipshape/measures/finding"

module Shipshape
  module Measures
    # Conditionals in an action that test domain state rather than an outcome.
    #
    # **This is the checkable half of "request handling decides nothing".** The whole rule is
    # a judgement and cannot be guarded; this part of it is mechanical, and it is the part
    # that matters:
    #
    #     if result.success?          # told an outcome — placement, and allowed
    #     if request.xhr?             # a property of the request — allowed
    #
    #     if @invoice.settled?        # asked the render payload a question — deciding
    #     if @booking.paid?           # the rule now has two owners
    #
    # **The tell is the receiver.** An instance variable in a controller is what the action
    # is about to render, so a predicate sent to one is the action interrogating its own
    # payload and acting on the answer. The decision belonged to whatever produced it, and
    # if that thing had answered with a `Result` there would be nothing to ask.
    #
    # Narrower than `Branches inside request handling` on purpose. That one counts every
    # conditional and says so; this one counts the conditionals that are almost certainly
    # rules in the wrong place.
    class ActionsBranchingOnDomainState
      TITLE = "Actions deciding on domain state"
      LAW = "no-decisions-in-request-handling"
      WHY = "An instance variable in a controller is what the action is about to render, " \
            "so a predicate sent to one is the action interrogating its own payload. The " \
            "decision belonged to whatever produced it."
      CAVEAT = "A few of these are placement rather than deciding — `stale?(@record)` for " \
               "HTTP caching, `@things.any?` for an empty state. Argue those one at a time; " \
               "the shape is right often enough to be worth reading every one."
      NOUN = "actions"
      SELF_RANKED = true

      CONDITIONS = %i[if case].freeze

      # Told, not asked. A Result is the answer to a question already decided elsewhere.
      OUTCOMES = %i[success? failure? success failure].freeze

      def call(sources)
        controllers(sources).flat_map do |source|
          ClassReading.classes(source).flat_map do |node|
            ClassReading.public_methods_of(node).map { |action| finding(source, action) }.compact
          end
        end.sort_by { |finding| -finding.context[:decisions] }
      end

      def population(sources)
        controllers(sources).sum do |source|
          ClassReading.classes(source).sum { |node| ClassReading.public_methods_of(node).length }
        end
      end

      def exemplars(sources)
        controllers(sources).flat_map do |source|
          ClassReading.classes(source).flat_map do |node|
            ClassReading.public_methods_of(node).reject { |action| decisions_in(action).any? }.map do |action|
              Finding.new(relative: source.relative, line: action.loc.line,
                          label: "##{action.method_name} asks the payload nothing")
            end
          end
        end
      end

      def proposal(findings)
        finding = findings.first
        return nil if finding.nil?

        <<~TEXT
          `#{finding.relative}:#{finding.line}` decides on `#{finding.context[:first]}` inside `##{finding.context[:action]}`.

          Whatever produced that object already knew the answer. Have it say so:

          ```ruby
          result = SomeCommand.call(...)          # answers success(...) or failure(:code)

          if result.success?                      # placement: which response to send
            redirect_to somewhere_path
          else
            render :show, status: :unprocessable_entity
          end
          ```

          The action then reads an outcome it was told rather than one it worked out — which
          is the whole of `tell-dont-ask` and `nothing-fails-quietly` in four lines: one
          forbids the question, the other obliges the answer.
        TEXT
      end

      private

      def controllers(sources)
        sources.select { |source| source.relative.split("/")[1] == "controllers" }
      end

      def finding(source, action)
        found = decisions_in(action)
        return nil if found.empty?

        Finding.new(
          relative: source.relative,
          line: found.first.loc.line,
          label: "##{action.method_name} — #{found.length} on domain state: #{found.map(&:source).uniq.join(", ")}",
          context: { action: action.method_name, decisions: found.length, first: found.first.source },
        )
      end

      def decisions_in(action)
        found = []
        ClassReading.walk(action.body) do |node|
          next unless CONDITIONS.include?(node.type)

          test = node.condition
          found.concat(asks(test))
        end
        found
      end

      # A predicate sent to an instance variable, at any depth of the condition — `if
      # @a.paid? && @b.ready?` is two.
      def asks(test)
        found = []
        ClassReading.walk(test) do |node|
          next unless node.send_type? && node.receiver
          next unless node.receiver.type == :ivar
          next if OUTCOMES.include?(node.method_name)

          found << node
        end
        found
      end
    end
  end
end
