# frozen_string_literal: true

class OnlyTheDoorIsCalled < ApplicationController
def show
  OtherQuestion.build_from(params)
end
end
