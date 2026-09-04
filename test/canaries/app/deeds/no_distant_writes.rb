# frozen_string_literal: true

class NoDistantWrites < Deed
def call
  $canary = 1
end
end
