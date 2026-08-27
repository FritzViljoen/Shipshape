# frozen_string_literal: true

module Shipshape
  # A name for "true or false", so `typed(tie, Boolean)` reads like every other assertion.
  #
  # Ruby has no Boolean class, and the usual workaround is to reopen `TrueClass` and
  # `FalseClass` to include a marker module. **We do not**, because a gem that reopens the
  # host application's core classes has changed something no caller can see from the call
  # site — the defect `nothing-travels-off-the-call-path` names. Two objects nobody owns
  # would start answering a question they were never asked.
  #
  # So this module is a name and nothing else. It is never included anywhere, and
  # `TypedArguments#typed` knows it by identity.
  module Boolean
    def self.to_s
      "Boolean"
    end

    def self.inspect
      "Boolean"
    end
  end
end
