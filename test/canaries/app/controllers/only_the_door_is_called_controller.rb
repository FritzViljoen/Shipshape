# frozen_string_literal: true

class OnlyTheDoorIsCalled < ApplicationController
def show
  OtherRead.build_from(params)
end
end
