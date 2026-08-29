# frozen_string_literal: true

class NoCallbacks < ApplicationRecord
  before_save :canary
end
