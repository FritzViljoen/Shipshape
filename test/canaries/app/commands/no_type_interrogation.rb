# frozen_string_literal: true

class NoTypeInterrogation < Write
def call
  @thing.is_a?(String)
end
end
