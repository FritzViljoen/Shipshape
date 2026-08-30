# frozen_string_literal: true

class NoEntryPointBypass < ApplicationController
def show
  Settle.new(amount: 1).send(:call)
end
end
