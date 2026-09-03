# frozen_string_literal: true

class NoAmbientReads < Write
def call
  Time.now
end
end
