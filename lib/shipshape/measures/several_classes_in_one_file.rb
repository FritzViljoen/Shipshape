# frozen_string_literal: true

require "shipshape/measures/finding"
require "shipshape/measures/naming"

module Shipshape
  module Measures
    # Files declaring more than one class.
    #
    # **A file name is the first index anybody has.** Where a file declares three classes,
    # two of them cannot be found by the name they are used under — not by a reader, not by
    # a grep, and not by the loader, which will autoload one of them and not the others.
    #
    # It is also how a second class comes to be written where nobody will look for it: the
    # cheapest place to put a new class is at the bottom of the file already open, and that
    # is the whole mechanism by which a codebase acquires objects with no home.
    #
    # Classes nested inside another class are not counted — those belong to the class around
    # them, which is a different thing from three peers sharing a file.
    class SeveralClassesInOneFile
      TITLE = "Files declaring several classes"
      LAW = "the-call-graph-is-declared"
      WHY = "A file name is the first index anybody has. Where a file declares three " \
            "classes, two cannot be found by the name they are used under — by a reader, a " \
            "grep, or the loader."
      NOUN = "files"
      SELF_RANKED = true
      # The label already lists the classes; the declaration line would repeat one of them.
      SHOW_SOURCE = false

      def call(sources)
        sources.map { |source| finding(source) }.compact.sort_by { |finding| -finding.context[:classes] }
      end

      def population(sources)
        sources.length
      end

      def exemplars(sources)
        sources.select { |source| standalone(source).length == 1 }.map do |source|
          Finding.new(relative: source.relative, line: 1, label: "one class, named after its file")
        end
      end

      def proposal(findings)
        finding = findings.first
        return nil if finding.nil?

        <<~TEXT
          `#{finding.relative}` declares #{finding.context[:classes]}: #{finding.context[:names].map { |name| "`#{name}`" }.join(", ")}.

          Give each one the file its name implies — #{finding.context[:names].map { |name| "`#{Naming.snake(name.split("::").last)}.rb`" }.join(", ")} — so that
          every one of them can be found by the name it is used under. Nothing else has to
          change: the classes are already written, and this only moves them somewhere a
          reader looking for them would think to look.
        TEXT
      end

      private

      def finding(source)
        classes = standalone(source)
        return nil if classes.length <= 1

        names = classes.map { |node| ClassReading.qualified_name(source.ast, node) }

        Finding.new(
          relative: source.relative,
          line: classes.last.loc.line,
          label: "#{classes.length} classes: #{names.join(", ")}",
          context: { classes: classes.length, names: names },
        )
      end

      def standalone(source)
        ClassReading.classes(source).reject { |node| ClassReading.owned_by_a_class?(source.ast, node) }
      end
    end
  end
end
