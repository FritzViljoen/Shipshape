# frozen_string_literal: true

class NoEmptyRescue < ApplicationController
def show
  risky
rescue StandardError
end
end
