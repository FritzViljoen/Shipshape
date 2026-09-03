# frozen_string_literal: true

class IoIsItsOwnKind < Write
def call
  Net::HTTP.get(URI("http://example.com"))
end
end
