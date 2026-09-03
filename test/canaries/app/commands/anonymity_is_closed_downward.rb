# frozen_string_literal: true

class AnonymityIsClosedDownward < Command
def anonymous_call
  OtherQuery.call
end
end
