# frozen_string_literal: true

module Shipshape
  # RuboCop's own "unrecognized cop or department NAME found in FILE" wording - see the coupling law.
  module UnrecognizedCops
    PATTERN = /unrecognized cop or department (\S+) found in/.freeze

    def self.named_in(text)
      text.to_s.scan(PATTERN).flatten.uniq.sort
    end
  end
end
