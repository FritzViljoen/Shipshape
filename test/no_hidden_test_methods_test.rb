# frozen_string_literal: true

require "test_helper"

# A zero-arity `test_*` method hidden below `private` or `protected` is silently never run.
class NoHiddenTestMethodsTest < Minitest::Test
  def test_no_zero_arity_test_method_is_hidden_by_private_or_protected
    hidden = Minitest::Runnable.runnables.each_with_object([]) do |klass, list|
      next unless klass < Minitest::Test

      names = (klass.private_instance_methods(false) + klass.protected_instance_methods(false))
              .select { |name| name =~ /\Atest_/ && klass.instance_method(name).arity.zero? }
      list.concat(names.map { |name| "#{klass}##{name}" })
    end

    assert_empty hidden, "hidden below `private`/`protected`, so Minitest never runs them"
  end
end
