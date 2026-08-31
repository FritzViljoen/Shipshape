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
  #
  # That is the failure this closes, and it is not hypothetical: shipshape's own cops were
  # once run over a 647-file tree and reported zero, which read as "this code is clean" and
  # meant "no glob matched, so nothing was inspected". Neither the unit tests nor
  # `rake test:removal` can catch it — both construct a config, and the thing that broke was
  # the *real* config's globs.
  #
  # So: plant one known violation per cop, at a path derived from **this application's own
  # kinds**, run **this application's own configuration** over it, and report any cop that
  # stayed silent. A cop that cannot find a violation written specifically for it is not
  # protecting anything.
  #
  # The canaries live in a temporary directory and are never written into the repository —
  # a planted violation checked in would fail the ordinary lint run for ever, and the first
  # fix would be to exclude it, which puts the hole back.
  class Canaries
    include TypedArguments

    Result = Struct.new(:fired, :silent, :unplanted, keyword_init: true) do
      def ok?
        silent.empty?
      end
    end

    # Each canary is the smallest thing its cop must refuse. `kind` picks which of the
    # application's globs the file is written under, so a repository that files commands
    # somewhere unusual is still tested where it actually keeps them.
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
      # Not kind-scoped either: the test trees are not a kind, and this is the only cop that
      # reads them.
      "Shipshape/NoTestFactories" => { path: "test/canary_factory_test.rb", raw: <<~RUBY },
        class CanaryFactoryTest
          def test_it
            create(:canary)
          end
        end
      RUBY
      # Not kind-scoped: a cadence is wrong wherever it is written, and the file it is usually
      # written in is not part of any tree the layout declares.
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
      "Shipshape/MixinsAddNothingPublic" => { path: "app/models/concerns/paying.rb", raw: <<~RUBY },
        module Paying
          def total
            1
          end
        end
      RUBY
    }.freeze

    # A canary sometimes needs a second file to be a violation at all.
    #
    # `EveryDoorChecksPermission` only speaks where authorisation was installed, and
    # `CallGraph` skips a constant it cannot resolve to a file — so the callee has to exist,
    # or the canary is inspected, found innocent, and the cop reports nothing while being
    # perfectly healthy.
    COMPANIONS = {
      "Shipshape/EveryDoorChecksPermission" => { "app/shipshape/permission.rb" => "module Permission\nend\n" },
      # Nothing is held to an audit log it never opted into, so the module has to exist.
      "Shipshape/OperationsReportWhatTheyDid" => {
        "app/shipshape/audit_log.rb" => "module AuditLog\nend\n",
      },
      "Shipshape/CallGraph" => { kind: "query", name: "OtherQuery" },
      "Shipshape/OnlyTheDoorIsCalled" => { kind: "query", name: "OtherQuery" },
      # The write has to reach something the layout calls a record, or the cop is
      # inspected, finds an unresolvable constant, and reports nothing while healthy.
      "Shipshape/QueriesOnlyRead" => { kind: "record", name: "Canary" },
      "Shipshape/PersonalDataIsDeclared" => {
        "app/shipshape/personal_data.rb" => "module PersonalData\n  COLUMNS = {}.freeze\nend\n",
      },
      # A module is only a violation because an operation includes it, so the including
      # operation is the canary's other half. Without it the module is somebody else's
      # business and the cop is silent while perfectly healthy.
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

    # Writes the canary tree, and its own `.rubocop.yml` beside it. **The configuration has
    # to live next to the canaries**: RuboCop resolves every `Kinds` glob against the
    # configuration file's directory, so pointed anywhere else the globs resolve back into
    # the application and the canaries are never inspected — silently, which is the exact
    # failure they exist to catch.
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

    # **One section per cop, never two.** The force-enable block was added as a second list
    # and re-declared cops the first list had already configured — so YAML took the later
    # entry and the `AutoCorrect: false` above it vanished. RuboCop said so ("is concealed by
    # line 54") and the words are easy to read past. The effect was that `rubocop -A` over
    # this tree would rewrite the canaries, which is the exact failure that setting exists to
    # prevent.
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

    # The cops that rewrite what they find. Being on this list is what stops a correction
    # here; nothing else confers it, so it cannot go stale silently.
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

    # **Every cop, not every enabled cop.** Filtering on the configuration meant a cop
    # shipped `Enabled: false` needed no canary — while the canon still demanded a law and a
    # test for it, so it read as fully covered while being unprovable. A cop that is off by
    # default is a legitimate thing; a cop nothing can prove fires is not. The planted tree
    # turns them all on for its own run, so the canary answers the question either way.
    def registered
      RuboCop::Cop::Registry.global.cops.map(&:cop_name).grep(%r{\AShipshape/}).sort
    end

    def settings
      @settings ||= Settings.layout(config)
    end

    # **Two cops may want the same companion**, and both `Shipshape/CallGraph` and
    # `Shipshape/OnlyTheDoorIsCalled` want `OtherQuery`. The second write is not the overwrite
    # the refusal exists to prevent — that one protects a tree somebody already had — so a
    # companion this run has already written is simply skipped.
    #
    # Found by re-planting from an empty directory, which nothing had done since the second of
    # those cops was added: files were only ever appended by hand, so `--plant` was broken and
    # the suite could not see it.
    def plant_companion(companion)
      return if companion.nil?
      return companion.each { |name, source| write_once(name, source) } unless companion[:kind]

      # **The file decides the constant, not the name given here** — because that is the rule
      # the resolver uses, and the glob may add to the name on its way to a path. A record
      # glob of `*_record.rb` turns `Canary` into `canary_record.rb`, whose constant is
      # `CanaryRecord`; writing `class Canary` there leaves the canary naming something that
      # resolves to nothing, and a cop that cannot resolve the constant reports nothing while
      # being perfectly healthy.
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

    # `app/records/**/*_record.rb` → `app/records/canary_no_callbacks_record.rb`. The glob is
    # the application's, so the canary lands where that application actually keeps the kind.
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

    # Nothing is overwritten, on the same terms as `shipshape install`: these paths collide
    # with the installer's own output, and `--plant --dir .` replaced `.rubocop.yml` and
    # `app/shipshape/command.rb` with stubs. A canary is worth nothing next to that.
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

    # Not `inspect`: that overrides `Object#inspect`, which Ruby calls regardless of
    # visibility, so `p canaries` shelled out to a RuboCop subprocess.
    def cops_that_fired
      # `-I` so the subprocess finds shipshape when it is on a load path rather than
      # installed — running from a checkout is the case that breaks otherwise, and it is the
      # case this gem is developed in.
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
