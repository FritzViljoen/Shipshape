# frozen_string_literal: true

module Shipshape
  # A name for true-or-false, never included: reopening TrueClass changes objects nobody owns.
  module Boolean
    def self.to_s
      "Boolean"
    end

    def self.inspect
      "Boolean"
    end
  end
end
