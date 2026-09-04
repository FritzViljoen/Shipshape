# frozen_string_literal: true

class NoTypeInterrogation < Deed
def call
  @thing.is_a?(String)
end
end
