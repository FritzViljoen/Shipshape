# frozen_string_literal: true

class OperationsAreLeaves < Deed
def self.call(**arguments)
  new(**arguments).call
end
end
