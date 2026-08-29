# frozen_string_literal: true

class NoEmptyRescue
def show
  risky
rescue StandardError
end
end
