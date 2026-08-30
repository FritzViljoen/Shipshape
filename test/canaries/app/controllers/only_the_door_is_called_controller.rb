# frozen_string_literal: true

class OnlyTheDoorIsCalled < ApplicationController
def show
  OtherQuery.build_from(params)
end
end
