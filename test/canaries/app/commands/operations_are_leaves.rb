# frozen_string_literal: true

class OperationsAreLeaves < Write
def self.call(**arguments)
  new(**arguments).call
end
end
