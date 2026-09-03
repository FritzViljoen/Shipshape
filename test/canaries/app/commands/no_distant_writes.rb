# frozen_string_literal: true

class NoDistantWrites < Command
def call
  $canary = 1
end
end
