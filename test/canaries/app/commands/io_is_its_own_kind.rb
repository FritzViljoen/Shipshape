# frozen_string_literal: true

class IoIsItsOwnKind < Command
def call
  Net::HTTP.get(URI("http://example.com"))
end
end
