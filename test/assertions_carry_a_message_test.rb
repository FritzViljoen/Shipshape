# frozen_string_literal: true

require "test_helper"
require "erb"
require "ripper"

# A bare assertion prints a diff and nothing else. In a file this gem installs into someone
# else's repository, the reader has no idea what shipshape is, so the diff is all they get.
# Scoped to the files brought to this standard — the rest of test/ still carries hundreds of
# bare assertions and is not this guard's job to fix by fiat.
# Watched to fail: delete the message off test/canon_test.rb's
# test_the_index_lists_every_law and this reddens, naming that line.
class AssertionsCarryAMessageTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  GUARDED = %w[
    test/canon_test.rb
    test/canaries_test.rb
    test/documents_have_one_shape_test.rb
    test/assertions_carry_a_message_test.rb
    lib/shipshape/templates/operations_expose_nothing_test.rb.tt
    lib/shipshape/templates/personal_data_is_erasable_test.rb.tt
  ].freeze

  # Minitest's own required-argument count per assertion; anything past it is the message.
  # `:splat` opts out of counting — see `last_arg_string_literal?`.
  MINIMUM_ARGS = {
    "assert" => 1, "refute" => 1,
    "assert_nil" => 1, "refute_nil" => 1,
    "assert_empty" => 1, "refute_empty" => 1,
    "assert_equal" => 2, "refute_equal" => 2,
    "assert_includes" => 2, "refute_includes" => 2,
    "assert_kind_of" => 2, "refute_kind_of" => 2,
    "assert_match" => 2, "refute_match" => 2,
    "assert_predicate" => 2, "refute_predicate" => 2,
    "assert_respond_to" => 2, "refute_respond_to" => 2,
    "assert_path_exists" => 1, "refute_path_exists" => 1,
    "assert_raises" => :splat,
  }.freeze

  # Only a name shaped like this is held to MINIMUM_ARGS at all.
  ASSERTION_NAME = /\A(?:assert|refute)(?:_\w+)?\z/.freeze

  def test_every_assertion_in_a_fixed_file_carries_a_message
    bare = GUARDED.flat_map { |relative| bare_assertions(relative) }

    assert_empty bare,
                 "A bare assert/refute prints only a diff. Add a trailing message arguing " \
                 "why the check exists, not what it checks: #{bare.join(', ')}. If you landed " \
                 "here because you just added a file to GUARDED, check it belongs: GUARDED is " \
                 "guards, which fail saying what a lost reader did wrong and what to do " \
                 "instead, never unit tests, whose diff already is the message. A message " \
                 "restating the assertion (\"expected 5, asserting 5\" in prose) is a second " \
                 "copy of the code and rots. The ~515 bare assertions in the other 56 test " \
                 "files are correct as they stand, not a backlog to clear."
  end

  private

  def bare_assertions(relative)
    path = File.join(ROOT, relative)

    if path.end_with?(".tt")
      [true, false].flat_map { |rspec| bare_in_template(path, relative, rspec) }.uniq
    else
      scan(File.read(path), relative).map { |line, name| "#{relative}:#{line} (#{name})" }
    end
  end

  # A rendered line number never resolves back to a `.tt` source line, so this quotes the
  # call, which also lets `.uniq` collapse its identical rspec-true/false renders.
  def bare_in_template(path, relative, rspec)
    source = render_template(path, rspec)
    lines = source.lines

    scan(source, "#{relative} (rendered with rspec=#{rspec})").map do |line, name|
      "#{relative}: `#{lines[line - 1]&.strip}` (#{name})"
    end
  end

  def render_template(path, rspec)
    ERB.new(File.read(path), trim_mode: "-").result(binding)
  end

  def scan(source, relative)
    sexp = Ripper.sexp(source)
    if sexp.nil?
      flunk "#{relative} does not parse as Ruby: Ripper.sexp returned nil, so this guard saw " \
            "no assertions at all instead of the syntax error that broke it. Fix the file " \
            "(or, for a template, whatever made its rendered output invalid Ruby)."
    end

    found = []
    walk(sexp, found, relative)
    found
  end

  def walk(node, found, relative)
    return unless node.is_a?(Array)

    case node[0]
    when :command
      check_call(node[1], node[2], found, relative)
    when :method_add_arg
      fcall = node[1]
      if fcall.is_a?(Array) && fcall[0] == :fcall
        check_call(fcall[1], arg_paren_args(node[2]), found, relative)
      end
    end

    node.each { |child| walk(child, found, relative) if child.is_a?(Array) }
  end

  def arg_paren_args(node)
    node.is_a?(Array) && node[0] == :arg_paren ? node[1] : nil
  end

  def check_call(ident_node, args_node, found, relative)
    return unless ident_node.is_a?(Array) && ident_node[0] == :@ident

    name = ident_node[1]
    return unless name.match?(ASSERTION_NAME)

    rule = MINIMUM_ARGS.fetch(name) do
      flunk "#{relative}:#{ident_node[2][0]} calls `#{name}`, an assertion not in " \
            "MINIMUM_ARGS. Add it there with its required arity (or `:splat`, like " \
            "assert_raises, if a trailing argument is a message only when it is a String " \
            "literal) before this guard can inspect it."
    end

    bare = rule == :splat ? !last_arg_string_literal?(args_node) : arg_count(args_node) <= rule
    found << [ident_node[2][0], name] if bare
  end

  def arg_count(args_node)
    return 0 unless args_node.is_a?(Array) && args_node[0] == :args_add_block

    list = args_node[1]
    list.is_a?(Array) ? list.length : 0
  end

  def last_arg_string_literal?(args_node)
    return false unless args_node.is_a?(Array) && args_node[0] == :args_add_block

    list = args_node[1]
    return false unless list.is_a?(Array) && !list.empty?

    last = list.last
    last.is_a?(Array) && last[0] == :string_literal
  end
end
