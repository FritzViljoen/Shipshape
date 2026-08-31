# frozen_string_literal: true

module Shipshape
  # Scrubs: one non-UTF-8 byte raises inside the shared resolver, taking every cop down with it.
  module SourceText
    def self.read(path)
      File.read(path, encoding: "UTF-8").scrub("")
    end

    def self.lines(path)
      read(path).lines
    end
  end
end
