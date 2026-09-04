# frozen_string_literal: true

class NoAmbientReads < Deed
def call
  Time.now
end
end
