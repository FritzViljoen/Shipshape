# frozen_string_literal: true

module Shipshape
  # Application source, read as text a regular expression can safely be run over.
  #
  # **`File.read` is not that**, and the difference is a crash rather than a wrong answer. A
  # file holding a byte that is not valid UTF-8 reads perfectly well and then raises
  # `ArgumentError: invalid byte sequence in UTF-8` the moment a regular expression touches
  # it. Ruby does not honour a `# encoding:` magic comment on `File.read`, so the file's own
  # declaration does not save you.
  #
  # **The damage was never limited to the odd file.** `Kinds` resolves a constant by reading
  # other files, and `Mixins` reads every operation in the repository before it can judge one
  # module — so a single non-UTF-8 file anywhere in a governed tree raised inside the shared
  # resolver and took down every kind-scoped cop for the whole run. The report said the cops
  # errored; it did not say the tree went unguarded. Found by stress test, not by review.
  #
  # So there is one way to read application source, and it scrubs.
  module SourceText
    def self.read(path)
      File.read(path, encoding: "UTF-8").scrub("")
    end

    def self.lines(path)
      read(path).lines
    end
  end
end
