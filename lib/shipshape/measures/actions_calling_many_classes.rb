# frozen_string_literal: true

require "set"
require "shipshape/measures/finding"
require "shipshape/measures/naming"

module Shipshape
  module Measures
    # Controller actions that name several different classes.
    class ActionsCallingManyClasses
      TITLE = "Actions orchestrating several classes"
      LAW = "no-decisions-in-request-handling"
      WHY = "Not a violation — several calls are allowed, and deciding is what is not. " \
            "This ranks the sequences worth naming: an action reaching eleven classes is a " \
            "piece of the business that cannot be tested, reused or read as a sequence."
      CAVEAT = "A ranking rather than a defect count: an action may call several " \
               "operations, provided it examines none of their results. Counts only classes " \
               "this repository declares — a framework or standard " \
               "library constant is not the application orchestrating anything. A job and a " \
               "domain class still weigh the same, so the ranking is the signal."

      NOUN = "actions"
      SELF_RANKED = true
      LIMIT = 1

      def population(sources)
        controllers(sources).sum { |source| actions(source, Set.new).length }
      end

      # Their own actions, already dispatching: what turns a diagnostic into a direction.
      def exemplars(sources)
        theirs = declared_in(sources)

        controllers(sources).flat_map do |source|
          actions(source, theirs).select { |_action, names| names.length == 1 }.map do |action, names|
            Finding.new(
              relative: source.relative,
              line: action.loc.line,
              label: "##{action.method_name} calls #{names.first} and nothing else",
            )
          end
        end
      end

      def call(sources)
        theirs = declared_in(sources)

        controllers(sources).flat_map do |source|
          actions(source, theirs).map { |action, names| finding(source, action, names) }.compact
        end.sort_by { |finding| -finding.context[:count] }
      end

      def proposal(findings)
        finding = findings.first
        return nil if finding.nil?

        action = finding.context[:action]
        name = Naming.operation_for(action: action, subject: finding.context[:subject])

        <<~TEXT
          `#{finding.relative}` — `##{action}` reaches #{finding.context[:count]} classes:
          #{finding.context[:names].map { |called| "`#{called}`" }.join(", ")}.

          Several calls are not the problem — deciding would be. What this many says is that
          the sequence is big enough to deserve a name, and a name it can be tested and run
          from a job under:

          ```ruby
          # app/workflows/#{Naming.snake(name)}.rb
          class #{name} < Workflow
            def call
              # the steps that are in ##{action} today, in order, each answering with a Result
            end
          end
          ```

          The action becomes one call. The sequence becomes testable without a request,
          reusable from a job, and readable top to bottom — and because a workflow spans
          transactions, each step has to be idempotent, which is work the controller was
          hiding rather than doing.

          **A workflow is optional and this is when it is worth it.** Two operations called
          from an action need no workflow: they are visibly two transactions and nobody is
          pretending otherwise. Eleven are a sequence somebody should own.
        TEXT
      end

      private

      def controllers(sources)
        sources.select { |source| source.relative.split("/")[1] == "controllers" }
      end

      def actions(source, theirs)
        ClassReading.classes(source).flat_map do |node|
          ClassReading.public_methods_of(node).map { |action| [action, called_in(action, theirs)] }
        end
      end

      # Only classes this repository declares: counting `Time` and `Rails` picked
      # `#twofa_enroll reaches 5: Time, ROTP::Base32, Rails…` as the worked example, which is a
      # list of libraries. Derived from what the files declare, not from a list that would rot.
      def declared_in(sources)
        found = Set.new
        sources.each do |source|
          ClassReading.walk(source.ast) do |node|
            found << node.children.first.source if %i[class module].include?(node.type)
          end
        end
        found
      end

      def finding(source, action, names)
        return nil if names.length <= LIMIT

        Finding.new(
          relative: source.relative,
          line: action.loc.line,
          label: "##{action.method_name} reaches #{names.length}: #{names.to_a.join(", ")}",
          context: {
            action: action.method_name,
            count: names.length,
            names: names.to_a,
            subject: subject_for(source),
          },
        )
      end

      def called_in(action, theirs)
        found = Set.new
        ClassReading.walk(action.body) do |node|
          next unless node.send_type? && node.receiver && node.receiver.const_type?

          name = node.receiver.source
          found << name if theirs.include?(name)
        end
        found
      end

      def subject_for(source)
        base = File.basename(source.relative, ".rb").delete_suffix("_controller")

        Naming.camel(base)
      end
    end
  end
end
