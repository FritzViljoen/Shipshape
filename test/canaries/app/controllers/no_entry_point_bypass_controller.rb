# frozen_string_literal: true

class NoEntryPointBypass < ApplicationController
def show
  Settle.send(:new, amount: 1)
end
end
