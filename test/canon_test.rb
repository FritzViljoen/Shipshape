# frozen_string_literal: true

require "test_helper"
require "shipshape/install"
require "yaml"

# The law and the cop are two halves of one fact, and the cop list is the whole enforcement
# surface, so it holds both ways. Watched to fail: rename a cop file without touching its law,
# add a cop with no law, or delete a cop's test, and one of the three checks reddens.
class CanonTest < Minitest::Test
  NON_RULE_DOCUMENTS = %w[README.md CLAUDE.md].freeze

  LAWS = Dir[File.expand_path("../docs/laws/*.md", __dir__)]
         .reject { |path| NON_RULE_DOCUMENTS.include?(File.basename(path)) }

  # The phrase is the declaration: writing it is what makes the law a convention.
  UNBUILT = "not built yet"

  REMOVAL_CLAIM = "Watched to fail"

  GUARD_LINE = /^- \*\*Guard:\*\* (.+?)(?:\n(?!  )|\z)/m
  COP_NAME = %r{`Shipshape/(\w+)`}

  # Being on this list is what makes a non-cop guard legitimate; nothing else grants it.
  SUITE_GUARDS = ["CanonTest", "CanariesTest", "generated_base_classes_test.rb",
                  "SanctionedWayComesFirstTest", "MarkdownLinksResolveTest",
                  "RuleCitationsResolveTest", "ConfigKindsAreSoundTest"].freeze


  # Being on this list is what grants the exemption; an app-facing cop comes off it.
  PROCEDURE_WOULD_NOT_HELP = {
    "EnforcementMessagesAreDocumentation" =>
      "guards this gem's own cops, so it never fires on an application at all.",
    "PresenceIsNotRedefined" =>
      "the fix is to delete a method, and nothing moves.",
    "PresentationHoldsNoRecords" =>
      "the fix is one line in a base class the application already has, and nothing moves.",
    "CommentBudget" =>
      "nothing is moved. The fix is to delete prose, or to put it in the law it paraphrases, " \
      "and which of the two is a judgement about that one comment.",
    "OperationsReportWhatTheyDid" =>
      "an installed base class lost a line and the fix is to put it back. Nothing is moved, " \
      "so there is no decomposition to describe — same position as its sibling below.",
    "EveryDoorChecksPermission" =>
      "authorisation is a rollout rather than a decomposition: nothing is moved, a check " \
      "is added. It reports zero until `shipshape install --auth` has been run.",
    "NoTestMixins" =>
      "the fix is one of two moves and deciding between them is the whole of the work: " \
      "inline the method into the one test that needs it, or add it to the base class in " \
      "the open. Unlike the operation-side module (`a-shared-concern.md`), a test mixin " \
      "carries no concerns-of-concerns, no captured ivars and no split-by-includer question.",
    "BaseTestClassGrowth" =>
      "the offence names the exact definition that grew the count. The fix is to delete it, " \
      "inline it into the one test that needs it, or accept it as a reviewed addition - " \
      "there is no multi-step decomposition to walk to find it.",
    "AnonymityIsClosedDownward" =>
      "the fix is a one-word decision — this operation is anonymous or it is not — and " \
      "nothing moves either way. It also reports zero until authorisation is installed, " \
      "because without it no operation is anonymous.",
    "KindIsInheritedNotOnlyPlaced" =>
      "the fix is naming the base class its own kind already declares. Nothing is moved, " \
      "and there is no decomposition to walk — the class was always meant to inherit it.",
  }.freeze

  ARCHITECTURE_WITHOUT_A_LAW = {
    "shipshape_routes" =>
      "a report, and `one-mechanism-guards-everything` says a guard is not one: it prints " \
      "every route with the permissions needed to reach it and fails nothing. Naming it on a " \
      "Guard line to satisfy this check would have made the word mean less.",
    "boolean" => "a name, so `Boolean` can be written in a type guard. It decides nothing.",
    "persistence" => "one definition of what a record is, used by the guards that have laws.",
  }.freeze

  def test_every_law_names_a_cop_that_exists_or_says_it_does_not
    missing = laws.reject do |law|
      law[:cops].all? { |cop| registered?(cop) } || law[:guard].downcase.include?(UNBUILT)
    end

    assert_empty missing.map { |law| "#{law[:name]} names #{law[:cops].join(', ')}" },
                 "A law naming a cop that does not exist reads as coverage. Build the cop, " \
                 "or write \"#{UNBUILT}\" in its Guard line and call it a convention."
  end

  def test_every_law_names_some_guard
    silent = laws.reject do |law|
      law[:cops].any? ||
        law[:guard].downcase.include?(UNBUILT) ||
        SUITE_GUARDS.any? { |guard| law[:guard].include?(guard) }
    end

    assert_empty silent.map { |law| law[:name] },
                 "A law whose Guard line names nothing passes every other check here " \
                 "vacuously. Name a cop, name a suite guard, or say \"#{UNBUILT}\"."
  end

  def test_every_cop_is_named_by_a_law
    claimed = laws.flat_map { |law| law[:cops] }.to_set

    assert_empty (registered_cops - claimed).to_a,
                 "A cop enforcing something no law wrote down is a rule with no reason " \
                 "attached. Write the law, or delete the cop."
  end

  def test_every_cop_has_a_test
    without = registered_cops.reject { |cop| File.exist?(test_path_for(cop)) }

    assert_empty without.to_a,
                 "A cop with no test may enforce nothing at all. Every guard is proven by " \
                 "removal: delete it, watch the test go red, restore it."
  end

  # Writing the claim is what makes a test file a guard that was watched to fail.
  def test_every_cop_test_names_the_removals_that_proved_it
    unproven = registered_cops.select do |cop|
      path = test_path_for(cop)

      File.exist?(path) && !File.read(path).include?(REMOVAL_CLAIM)
    end

    assert_empty unproven.to_a,
                 "`a-guard-states-its-limit` requires every guard to be proven by removal. " \
                 "Delete the guard, watch the test go red, restore it — then say so in a " \
                 "\"#{REMOVAL_CLAIM}\" comment naming which removal reddened which test."
  end

  def test_every_law_states_its_guards_limit
    silent = laws.reject { |law| law[:body].include?("**Guard's limit:**") }

    assert_empty silent.map { |law| law[:name] },
                 "A guard that does not say what it misses is read as covering everything."
  end

  # The third direction: a cop and a law hold each other above, and nothing held the base
  # classes, so one could enforce a rule no document stated. It had happened twice.
  def test_every_installed_file_is_named_by_a_law
    guards = laws.map { |law| law[:guard] }.join("\n")

    unclaimed = installed.reject do |file|
      ARCHITECTURE_WITHOUT_A_LAW.key?(file) ||
        guards.include?("#{file}.rb") || guards.include?("#{file}.rake")
    end

    assert_empty unclaimed,
                 "These are installed into an application and constrain what it can do, and " \
                 "no law's Guard line names them. Write the law, name the file in its Guard " \
                 "line, or declare it on ARCHITECTURE_WITHOUT_A_LAW with the reason."
  end

  def test_no_law_names_a_file_that_is_not_installed
    suite = SUITE_GUARDS.map { |guard| guard.sub(/\.rb\z/, "") }
    named = laws.flat_map { |law| law[:guard].scan(/`(\w+)\.rb`/).flatten }.uniq
    missing = named - installed - suite

    assert_empty missing,
                 "A law naming a generated file that nobody installs is a rule with no " \
                 "mechanism behind it."
  end

  # A base class including `TypedArguments` is one whose initializer is meant to be asserted, so
  # a cop not scoped to that kind ships machinery nothing requires. It happened to `shape`.
  def test_every_base_class_that_types_its_arguments_is_a_kind_the_cop_covers
    covered = default_config.fetch("Shipshape/TypedArguments").fetch("Kinds")

    missing = kinds_of_templates_including("TypedArguments").reject { |kind| covered.include?(kind) }

    assert_empty missing,
                 "These kinds ship a base class that includes TypedArguments, so their " \
                 "initializers are meant to be asserted — but Shipshape/TypedArguments is " \
                 "not scoped to them, so nothing requires it."
  end

  # Without a procedure, an agent handed 29,644 offences has an enumeration and no method.
  def test_every_cop_has_a_procedure_that_names_it
    prose = Dir[File.expand_path("../docs/decomposing/*.md", __dir__)]
            .reject { |path| NON_RULE_DOCUMENTS.include?(File.basename(path)) }
            .map { |path| File.read(path) }.join("\n")

    orphans = registered_cops.reject do |cop|
      PROCEDURE_WOULD_NOT_HELP.key?(cop) || prose.include?(cop)
    end

    assert_empty orphans.to_a,
                 "No procedure in docs/decomposing names these, so an agent meeting one is " \
                 "told the code is wrong and not how to move it. Write the procedure, name " \
                 "the cop in it, or declare it on PROCEDURE_WOULD_NOT_HELP with the reason."
  end

  def test_the_decomposing_index_lists_every_procedure
    index = File.read(File.expand_path("../docs/decomposing/README.md", __dir__))

    missing = Dir[File.expand_path("../docs/decomposing/*.md", __dir__)]
              .map { |path| File.basename(path) }
              .reject { |name| NON_RULE_DOCUMENTS.include?(name) || index.include?("(#{name})") }

    assert_empty missing, "A procedure nothing links to is one nobody will find."
  end

  # A glob carrying a filename suffix cannot see a concerns directory, and a concern included
  # into a kind IS that kind. `app/controllers/**/*_controller.rb` left lobsters' `story_finder`
  # reporting clean while it read two records, took a raw parameter into `find_by` and branched
  # on `is_admin?`. Derived from the globs, so the next kind added cannot repeat it.
  def test_every_governed_tree_governs_its_concerns
    globs = kinds.values.flatten
    flags = File::FNM_PATHNAME | File::FNM_EXTGLOB

    blind = kinds.flat_map do |kind, own|
      own.filter_map { |glob| glob[%r{\A(?:app|packs/\*)/([^/*]+)/}, 1] }.uniq.reject do |root|
        globs.any? { |glob| File.fnmatch?(glob, "app/#{root}/concerns/anything.rb", flags) }
      end.map { |root| "#{kind}: app/#{root}/concerns" }
    end

    assert_empty blind,
                 "A concern included into a kind is that kind, and a glob with a filename " \
                 "suffix cannot see one. Declare the concerns directory beside the tree."
  end

  def test_the_index_lists_every_law
    index = File.read(File.expand_path("../docs/laws/README.md", __dir__))

    assert_empty laws.map { |law| law[:name] }.reject { |name| index.include?("(#{name}.md)") },
                 "A law nothing links to is one nobody will find. Add it to docs/laws/README.md."
  end

  private

  def kinds
    default_config.fetch("Shipshape/CallGraph").fetch("Kinds")
  end

  def default_config
    @default_config ||= YAML.load_file(File.expand_path("../config/default.yml", __dir__))
  end

  def kinds_of_templates_including(mixin)
    base_classes = default_config.fetch("Shipshape/CallGraph").fetch("BaseClasses")

    Dir[File.expand_path("../lib/shipshape/templates/*.rb.tt", __dir__)].filter_map do |path|
      next unless File.read(path).include?("include #{mixin}")

      constant = File.basename(path, ".rb.tt").split("_").map(&:capitalize).join
      base_classes.find { |_, names| names.include?(constant) }&.first
    end.uniq.sort
  end

  def installed
    Shipshape::Install::FILES + Shipshape::Install::TESTS + Shipshape::Install::TASKS +
      Shipshape::Install::BASE_TESTS
  end

  def laws
    @laws ||= LAWS.sort.map do |path|
      body = File.read(path)
      # Every guard line, not the first: a law may be held by more than one cop, and reading
      # only the first made the second an orphan.
      guard = body.scan(GUARD_LINE).flatten.join("\n")

      {
        name: File.basename(path, ".md"),
        body: body,
        guard: guard,
        cops: guard.scan(COP_NAME).flatten.uniq,
      }
    end
  end

  # Off the registry, never a list here: a list would be a second copy of a fact.
  def registered_cops
    @registered_cops ||= RuboCop::Cop::Registry.global.cops
                                               .map(&:cop_name)
                                               .grep(%r{\AShipshape/})
                                               .map { |name| name.split("/").last }
                                               .to_set
  end

  def registered?(cop)
    registered_cops.include?(cop)
  end

  def test_path_for(cop)
    snake = cop.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase

    File.expand_path("rubocop/cop/shipshape/#{snake}_test.rb", __dir__)
  end
end
