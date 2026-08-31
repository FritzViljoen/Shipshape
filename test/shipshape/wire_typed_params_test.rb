# frozen_string_literal: true

require "test_helper"
require "shipshape/wire_typed_params"
require "tmpdir"

# Watched to fail: deleting the `include TypedParams` check in #call reddens the idempotence case,
# and neutering #wired reddens the wiring case. The reason this operation exists at all: writing
# the concern is not including it, and a concern nobody includes parses nothing while the
# application looks equipped.
class WireTypedParamsTest < Minitest::Test
  CONTROLLER = <<~RUBY
    # frozen_string_literal: true

    class ApplicationController < ActionController::Base
      protect_from_forgery with: :exception

      def current_user
        @current_user
      end
    end
  RUBY

  def test_it_includes_the_concern_under_the_class_line
    in_app(CONTROLLER) do |root|
      outcome, = Shipshape::WireTypedParams.new(root: root).call

      assert_equal :wired, outcome
      assert_match(/class ApplicationController < ActionController::Base\n  include TypedParams\n/, read(root))
    end
  end

  def test_it_leaves_everything_else_alone
    in_app(CONTROLLER) do |root|
      Shipshape::WireTypedParams.new(root: root).call
      source = read(root)

      assert_includes source, "protect_from_forgery with: :exception"
      assert_includes source, "def current_user"
      assert_equal CONTROLLER.lines.length + 1, source.lines.length
    end
  end

  def test_it_is_idempotent
    in_app(CONTROLLER) do |root|
      Shipshape::WireTypedParams.new(root: root).call
      once = read(root)

      outcome, = Shipshape::WireTypedParams.new(root: root).call

      assert_equal :already, outcome
      assert_equal once, read(root),
        "Run it twice and the second run changes nothing. A legacy base controller has years of other people's decisions in it, and an installer that edits it again on every run is one nobody will let near their repository."
    end
  end

  def test_a_missing_controller_is_reported_not_created
    Dir.mktmpdir("shipshape-app") do |root|
      outcome, path = Shipshape::WireTypedParams.new(root: root).call

      assert_equal :no_controller, outcome
      assert_equal "app/controllers/application_controller.rb", path
      refute_path_exists File.join(root, path),
        "Saying nothing here would leave the seam open while the install reported success."
    end
  end

  def test_a_file_with_no_class_in_it_is_reported_rather_than_mangled
    in_app("# just a comment\n") do |root|
      outcome, = Shipshape::WireTypedParams.new(root: root).call

      assert_equal :no_controller, outcome
      assert_equal "# just a comment\n", read(root)
    end
  end

  def test_the_indentation_follows_the_class_line
    in_app("module Admin\n  class BaseController\n  end\nend\n") do |root|
      Shipshape::WireTypedParams.new(root: root).call

      assert_includes read(root), "  class BaseController\n    include TypedParams\n"
    end
  end

  def test_the_root_is_asserted_at_the_seam
    assert_raises(ArgumentError) { Shipshape::WireTypedParams.new(root: nil) }
  end

  private

  def in_app(controller)
    Dir.mktmpdir("shipshape-app") do |root|
      target = File.join(root, Shipshape::WireTypedParams::CONTROLLER)
      FileUtils.mkdir_p(File.dirname(target))
      File.write(target, controller)

      yield(root)
    end
  end

  def read(root)
    File.read(File.join(root, Shipshape::WireTypedParams::CONTROLLER))
  end
end
