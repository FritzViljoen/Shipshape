# frozen_string_literal: true

require "erb"
require "fileutils"
require "json"
require "open3"
require "pathname"
require "rubocop"
require "shipshape/error"
require "shipshape/settings"
require "shipshape/typed_arguments"

module Shipshape
  # **A guard that does not run reports the same thing as a guard that finds nothing.**
  class Canaries
    include TypedArguments

    Result = Struct.new(:fired, :silent, :unplanted, keyword_init: true) do
      def ok?
        silent.empty?
      end
    end

    # The smallest thing its cop must refuse. `kind` picks which glob it is written under.
    PLANTED = {
      "Shipshape/CallGraph" => { kind: "query", body: <<~RUBY },
        def call
          OtherQuery.call
        end
      RUBY
      "Shipshape/NoAmbientReads" => { kind: "command", body: <<~RUBY },
        def call
          Time.now
        end
      RUBY
      "Shipshape/NoDistantWrites" => { kind: "command", body: <<~RUBY },
        def call
          $canary = 1
        end
      RUBY
      "Shipshape/NoTypeInterrogation" => { kind: "command", body: <<~RUBY },
        def call
          @thing.is_a?(String)
        end
      RUBY
      "Shipshape/NoGeneratedInterfaces" => { kind: "command", body: <<~RUBY },
        def call
          define_method(:x) { 1 }
        end
      RUBY
      "Shipshape/TypedArguments" => { kind: "command", body: <<~RUBY },
        def initialize(unasserted:)
          @unasserted = unasserted
        end
      RUBY
      "Shipshape/OneOperationOneClass" => { kind: "command", body: <<~RUBY },
        def call; end

        def second_operation; end
      RUBY
      "Shipshape/NoCallbacks" => { kind: "record", body: "  before_save :canary\n" },
      "Shipshape/PersistenceHoldsNoBehaviour" => { kind: "record", body: <<~RUBY },
        def canary_rule
          1
        end
      RUBY
      "Shipshape/PresenceIsNotRedefined" => { kind: "shape", body: <<~RUBY },
        def present?
          false
        end
      RUBY
      "Shipshape/ShapeIsComposed" => { kind: "shape", body: <<~RUBY },
        def initialize(supplier_name:, supplier_email:)
          @supplier_name = supplier_name
        end
      RUBY
      "Shipshape/NoDecisionsInRequestHandling" => { kind: "request_handling", body: <<~RUBY },
        def show
          render :x if @canary.cancelled?
        end
      RUBY
      "Shipshape/NoInlineParamParse" => { kind: "request_handling", body: <<~RUBY },
        def show
          Date.parse(params[:on])
        end
      RUBY
      "Shipshape/NoUnparsedLookup" => { kind: "request_handling", body: <<~RUBY },
        def show
          CanaryRecord.find(params[:id])
        end
      RUBY
      "Shipshape/NoSilentCoercion" => { kind: "request_handling", body: <<~RUBY },
        def show
          params[:page].to_i
        end
      RUBY
      "Shipshape/NoEmptyRescue" => { kind: "request_handling", body: <<~RUBY },
        def show
          risky
        rescue StandardError
        end
      RUBY
      "Shipshape/OnlyTheDoorIsCalled" => { kind: "request_handling", body: <<~RUBY },
        def show
          OtherQuery.build_from(params)
        end
      RUBY
      "Shipshape/NoEntryPointBypass" => { kind: "request_handling", body: <<~RUBY },
        def show
          Settle.send(:new, amount: 1)
        end
      RUBY
      "Shipshape/AnonymityIsClosedDownward" => { kind: "command", body: <<~RUBY },
        def anonymous_call
          OtherQuery.call
        end
      RUBY
      "Shipshape/OperationsAreLeaves" => { kind: "command", body: <<~RUBY },
        def self.call(**arguments)
          new(**arguments).call
        end
      RUBY
      "Shipshape/WorkflowsBranchOnOutcome" => { kind: "workflow", body: <<~RUBY },
        def call
          charge = ChargeCard.call

          success(1) if charge.value.total > 100
        end
      RUBY
      "Shipshape/AggregationIsReadable" => { kind: "workflow", body: <<~RUBY },
        def call
          SomeCommand.call
        end
      RUBY
      # Not kind-scoped: these read paths of their own, so the canary goes there directly.
      #
      # `NoTypeSuffix` also belongs here even though it IS kind-scoped: the offence is the
      # class's own name, and `wrap` names every kind-scoped canary after the cop under test
      # (`NoTypeSuffix`, which does not end in a banned suffix) — a body-only canary could
      # never carry a bad name, so it is written raw instead.
      "Shipshape/NoTypeSuffix" => { path: "app/commands/canary_service.rb", raw: <<~RUBY },
        class CanaryService < Command
          def call; end
        end
      RUBY
      "Shipshape/NoTestFactories" => { path: "test/canary_factory_test.rb", raw: <<~RUBY },
        class CanaryFactoryTest
          def test_it
            create(:canary)
          end
        end
      RUBY
      "Shipshape/NothingSchedulesWork" => { path: "config/schedule.rb", raw: <<~RUBY },
        every 1.day, at: "3:00 am" do
          runner "CanarySettle.call"
        end
      RUBY
      "Shipshape/NoNullableColumns" => { path: "db/migrate/20200101000000_canary.rb", raw: <<~RUBY },
        class Canary < ActiveRecord::Migration[7.0]
          def change
            add_column :canaries, :thing, :string, null: true
          end
        end
      RUBY
      "Shipshape/NoColumnDefaults" => { path: "db/migrate/20200102000000_canary_default.rb", raw: <<~RUBY },
        class CanaryDefault < ActiveRecord::Migration[7.0]
          def change
            add_column :canaries, :state, :string, null: false, default: "held"
          end
        end
      RUBY
      # Standing on its own, because a class below a governed base is swept by it — planting
      # `class X < Shape` proved nothing and the cop was silent while perfectly healthy.
      "Shipshape/PresentationHoldsNoRecords" => { path: "app/shapes/canary_unswept.rb", raw: <<~RUBY },
        class CanaryUnswept
          def initialize(person:)
            @person = person
          end
        end
      RUBY
      "Shipshape/CommentBudget" => { path: "lib/canary_prose.rb", raw: <<~RUBY },
        # One line of code, and eight of prose about it, which is what the budget refuses.
        # The rule this paraphrases has a home, and that home is the one that gets reviewed
        # when the rule changes. Nothing points here, so nothing corrects this when it goes
        # stale, and a reader a year out cannot tell which half is still true.
        # A comment that fails is worse than one that is missing.
        # This canary is prose about nothing, which is the point.
        # It must outweigh the code below it by more than a tenth.
        # It does.
        CANARY = 1
      RUBY
      "Shipshape/EnforcementMessagesAreDocumentation" => { path: "lib/canary_cop.rb", raw: <<~RUBY },
        class CanaryCop < Base
          MSG = "Do not do that."

          def on_send(node)
            add_offense(node)
          end
        end
      RUBY
      "Shipshape/EveryDoorChecksPermission" => { path: "app/shipshape/command.rb", raw: <<~RUBY },
        class Command
          def self.call(**arguments)
            new(**arguments).call
          end
        end
      RUBY
      "Shipshape/PersonalDataIsDeclared" => { path: "db/schema.rb", raw: <<~RUBY },
        create_table "canaries" do |t|
          t.string "email"
        end
      RUBY
      "Shipshape/CommandsProveIdempotence" => { kind: "command", body: <<~RUBY },
        def call
          success(1)
        end
      RUBY
      "Shipshape/AssociationsSurviveErasure" => { kind: "record", body: <<~RUBY },
        has_many :comments
      RUBY
      "Shipshape/IoIsItsOwnKind" => { kind: "command", body: <<~RUBY },
        def call
          Net::HTTP.get(URI("http://example.com"))
        end
      RUBY
      "Shipshape/QueriesOnlyRead" => { kind: "query", body: <<~RUBY },
        def call
          CanaryRecord.create!(name: "x")
        end
      RUBY
      "Shipshape/OperationsReportWhatTheyDid" => { path: "app/shipshape/workflow.rb", raw: <<~RUBY },
        class Workflow
          def self.call(**arguments)
            new(**arguments).__perform__
          end
        end
      RUBY
      "Shipshape/OnlyOperationsCalculate" => { kind: "view_component", body: <<~RUBY },
        def call
          @adults + @children
        end
      RUBY
      "Shipshape/MixinsAddNothingPublic" => { path: "app/models/concerns/paying.rb", raw: <<~RUBY },
        module Paying
          def total
            1
          end
        end
      RUBY
    }.freeze

    # A canary sometimes needs a second file to be a violation at all: a cop that skips an
    # unresolvable constant reports nothing while being perfectly healthy.
    COMPANIONS = {
      "Shipshape/EveryDoorChecksPermission" => { "app/shipshape/permission.rb" => "module Permission\nend\n" },
      "Shipshape/OperationsReportWhatTheyDid" => {
        "app/shipshape/audit_log.rb" => "module AuditLog\nend\n",
      },
      "Shipshape/CallGraph" => { kind: "query", name: "OtherQuery" },
      "Shipshape/OnlyTheDoorIsCalled" => { kind: "query", name: "OtherQuery" },
      "Shipshape/QueriesOnlyRead" => { kind: "record", name: "Canary" },
      "Shipshape/PersonalDataIsDeclared" => {
        "app/shipshape/personal_data.rb" => "module PersonalData\n  COLUMNS = {}.freeze\nend\n",
      },
      # A module is only a violation because an operation includes it.
      "Shipshape/MixinsAddNothingPublic" => {
        "app/commands/pays_something.rb" => "class PaysSomething < Command\n  include Paying\n\n  def call; end\nend\n",
      },
    }.freeze

    DIRECTORY = "test/canaries"

    def initialize(config:, root: DIRECTORY, inherits: nil)
      @config = config
      @root = typed(root, String)
      @inherits = inherits
    end

    # The configuration has to live next to the canaries: RuboCop resolves every glob against
    # its own directory, so anywhere else they resolve back into the application, silently.
    def plant
      FileUtils.mkdir_p(root)
      @written = []
      write(".rubocop.yml", configuration)

      planted.each do |cop, relative|
        canary = PLANTED.fetch(cop)

        write(relative, canary[:raw] || wrap(canary.fetch(:kind), cop, canary.fetch(:body)))
        plant_companion(COMPANIONS[cop])
      end

      planted.length
    end

    def call
      seen = cops_that_fired

      Result.new(
        fired: (planted.keys & seen).sort,
        silent: (planted.keys - seen).sort,
        unplanted: (registered - PLANTED.keys).sort,
      )
    end

    private

    attr_reader :config, :root, :inherits

    # One section per cop, never two: a second list re-declared cops the first had configured,
    # YAML took the later entry, and the `AutoCorrect: false` above it vanished.
    def configuration
      <<~YAML
        # Generated by `shipshape canaries --plant`. Each file here is a deliberate
        # violation, planted so a cop that stops running is noticed — a guard that does not
        # run reports the same thing as a guard that finds nothing.
        #
        # Exclude this directory from your ordinary lint run, or it fails for ever.
        inherit_from:
          - #{inherits || relative_default}

        # Every cop is on for this run whatever it ships as: a cop that is off by default is
        # still one the canon claims, so it still has to be shown firing. And every file here
        # is a deliberate violation, so the correcting cops must not correct them — `rubocop
        # -A` over this tree would rewrite the canaries, and the next run would blame the kind
        # globs for a hole the correction made.
        #{cop_settings}

        AllCops:
          NewCops: disable
          SuggestExtensions: false
      YAML
    end

    # Being on this list is what stops a correction here; nothing else confers it.
    CORRECTING = %w[
      Shipshape/NoSilentCoercion
      Shipshape/NoUnparsedLookup
      Shipshape/NoInlineParamParse
      Shipshape/MixinsAddNothingPublic
      Shipshape/OneOperationOneClass
    ].freeze

    def cop_settings
      registered.map do |cop|
        lines = ["#{cop}:", "  Enabled: true"]
        lines << "  AutoCorrect: false" if CORRECTING.include?(cop)
        lines.join("\n")
      end.join("\n")
    end

    def relative_default
      Pathname.new(::Shipshape::CONFIG_DEFAULT).relative_path_from(Pathname.new(File.expand_path(root)))
    rescue ArgumentError
      ::Shipshape::CONFIG_DEFAULT.to_s
    end

    def planted
      @planted ||= (registered & PLANTED.keys).to_h do |cop|
        canary = PLANTED.fetch(cop)

        [cop, canary[:path] || path_for(canary.fetch(:kind), cop)]
      end
    end

    # Every cop, not every enabled one: filtering on the configuration let a cop shipped
    # `Enabled: false` read as fully covered while nothing could prove it fires.
    def registered
      RuboCop::Cop::Registry.global.cops.map(&:cop_name).grep(%r{\AShipshape/}).sort
    end

    def settings
      @settings ||= Settings.layout(config)
    end

    # Two cops may want the same companion, and the second write is not the overwrite the
    # refusal exists to prevent. Found by re-planting from an empty directory, which nothing
    # had done since the second such cop was added: `--plant` was broken and unnoticed.
    def plant_companion(companion)
      return if companion.nil?
      return companion.each { |name, source| write_once(name, source) } unless companion[:kind]

      # The file decides the constant, not the name given here: a `*_record.rb` glob turns
      # `Canary` into `CanaryRecord`, and a canary naming something unresolvable proves nothing.
      kind = companion.fetch(:kind)
      relative = path_for(kind, companion.fetch(:name))
      constant = constant_for(relative)
      superclass = Array(settings.base_classes[kind]).first

      write_once(relative, "class #{constant} < #{superclass}\nend\n")
    end

    def constant_for(relative)
      File.basename(relative, ".rb").split("_").map(&:capitalize).join
    end

    def write_once(relative, source)
      return if @written.include?(relative)

      write(relative, source)
    end

    def path_for(kind, cop)
      glob = Array(settings.kinds[kind]).first
      raise Error, "shipshape: this configuration declares no path for #{kind}" unless glob

      directory = glob.split("/").take_while { |part| !part.include?("*") }.join("/")
      basename = File.basename(glob).sub("*", slug(cop))

      File.join(directory, basename)
    end

    def wrap(kind, cop, body)
      superclass = Array(settings.base_classes[kind]).first

      name = slug(cop).split("_").map(&:capitalize).join
      declaration = superclass ? "class #{name} < #{superclass}" : "class #{name}"

      "# frozen_string_literal: true\n\n#{declaration}\n#{body}end\n"
    end

    def slug(cop)
      cop.split("/").last.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
    end

    # Never overwrites: `--plant --dir .` replaced `.rubocop.yml` and `command.rb` with stubs.
    def write(relative, source)
      target = File.join(root, relative)
      raise Error, "shipshape: #{relative} already exists; canaries never overwrite" if File.exist?(target)

      @written << relative
      write!(relative, source)
    end

    def write!(relative, source)
      target = File.join(root, relative)
      FileUtils.mkdir_p(File.dirname(target))
      File.write(target, source)
    end

    # Not `inspect`: Ruby calls that regardless of visibility, so `p canaries` shelled out.
    def cops_that_fired
      # `-I` so the subprocess finds shipshape from a checkout rather than an installed gem.
      command = [RbConfig.ruby, "-I", File.expand_path("../..", __dir__) + "/lib",
                 rubocop, "--require", "shipshape", "--only", "Shipshape",
                 "--format", "json", "--no-color", "."]

      out, err, = Open3.capture3(*command, chdir: root)
      report = out[/\{.*\}/m]
      raise Error, "shipshape: rubocop produced no report for the canaries: #{err.strip}" unless report

      JSON.parse(report)["files"].flat_map { |file| file["offenses"].map { |o| o["cop_name"] } }.uniq
    end

    def rubocop
      @rubocop ||= Gem.bin_path("rubocop", "rubocop")
    rescue Gem::Exception
      raise Error, "shipshape: rubocop is not installed in this environment."
    end
  end
end
