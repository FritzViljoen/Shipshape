# frozen_string_literal: true

class OperationsAreLeaves < Command
def self.call(**arguments)
  new(**arguments).call
end
end
