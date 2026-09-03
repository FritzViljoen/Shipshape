# frozen_string_literal: true

class WritesProveIdempotence < Write
def call
  success(1)
end
end
