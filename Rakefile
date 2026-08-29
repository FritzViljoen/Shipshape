# frozen_string_literal: true

require "rake/testtask"

# `test/removal_test.rb` spawns a Ruby process per cop to perform the removals for real, so
# it is minutes rather than seconds and is not part of the default run. It is the check that
# `a-guard-states-its-limit` actually asks for — run it on any change to a cop.
REMOVAL = "test/removal_test.rb"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"].exclude(REMOVAL)
  t.warning = false
end

namespace :test do
  desc "Neuter each cop in turn and confirm its own test goes red"
  Rake::TestTask.new(:removal) do |t|
    t.libs << "test"
    t.libs << "lib"
    t.test_files = [REMOVAL]
    t.warning = false
  end
end

task default: :test
