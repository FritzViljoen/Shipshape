# frozen_string_literal: true

require "set"
require "shipshape/typed_arguments"

module Shipshape
  # Which module names an operation mixes in.
  #
  # **The question runs backwards from every other one in this gem**, which is why it needs
  # its own class. `Kinds` asks what a file is; this asks who includes it. A module cannot
  # answer for itself: `app/models/concerns/paying.rb` is legitimate in a shape, whose whole
  # job is to be read, and illegitimate in a command, which exposes one method. Nothing in
  # the module's own file separates those, so the answer is in its callers.
  #
  # So the operation trees are scanned once and every `include`/`prepend` written in them is
  # collected. A module named there inherits the operation's rules; a module named nowhere is
  # somebody else's business.
  #
  # **Names, not files.** Resolving the name to a file was the first attempt and it was
  # wrong: `Kinds` resolves constants only within declared kind globs, so `app/models/
  # concerns/paying.rb` came back nil and the module the rule most exists for was the one it
  # could not see. A name compares against the name the module declares, wherever it lives.
  #
  # **Read rather than parsed**, matching `Kinds#superclass_in` — a regular expression over
  # source. A dynamically-computed include is invisible, and so is one reached through an
  # alias. Both fail open, and the law that names this says so.
  class Mixins
    include TypedArguments

    INCLUDE = /^\s*(?:include|prepend)\s+((?:::)?[A-Z][\w:]*)/.freeze

    def initialize(settings:, base_dir:, operation_kinds:)
      @settings = typed(settings, Settings)
      @base_dir = typed(base_dir, String)
      @operation_kinds = typed(operation_kinds, Array)
      @written_names = nil
    end

    # Does an operation somewhere include this module?
    #
    # `include Paying` matches a module declared as `Paying` and one declared as
    # `Billing::Paying`, because an operation inside `Billing` writes the short form and
    # nothing here loads the application to tell the two apart. **That over-fires** where two
    # different modules share a last segment and only one is a mixin — and the cost of over-
    # firing is being told to make a module's methods private, which is a defensible thing to
    # be told. It never under-fires, and a guard that misses is the worse failure.
    def mixed_into_an_operation?(declared_name)
      return false if declared_name.nil?

      typed(declared_name, String)
      written_names.any? { |written| names_the_same_module?(written, declared_name) }
    end

    private

    attr_reader :settings, :base_dir, :operation_kinds

    def names_the_same_module?(written, declared)
      written == declared || declared.end_with?("::#{written}")
    end

    def written_names
      @written_names ||= operation_files.flat_map { |file| included_in(file) }.to_set
    end

    def included_in(file)
      File.read(file).scan(INCLUDE).flatten.map { |name| name.sub(/\A::/, "") }
    rescue SystemCallError
      # A file that vanished between the glob and the read is not this cop's business.
      []
    end

    # Every file of an operation kind, from the layout's own globs. The tree is read once
    # and the result memoised for the run, which is what makes this affordable.
    def operation_files
      settings.kinds
              .select { |kind, _globs| operation_kinds.include?(kind) }
              .values.flatten
              .flat_map { |glob| Dir.glob(File.join(base_dir, glob)) }
              .uniq
              .select { |path| File.file?(path) }
    end
  end
end
