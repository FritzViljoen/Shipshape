# frozen_string_literal: true

class NoTypeInterrogation < Command
def call
  @thing.is_a?(String)
end
end
