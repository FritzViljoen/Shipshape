# frozen_string_literal: true

class NoDistantWrites < Write
def call
  $canary = 1
end
end
