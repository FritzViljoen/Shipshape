# frozen_string_literal: true

class OnlyOperationsCalculate < ApplicationViewComponent
def call
  @adults + @children
end
end
