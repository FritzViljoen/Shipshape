# frozen_string_literal: true

class NoDecisionsInRequestHandling < ApplicationController
def show
  render :x if @canary.cancelled?
end
end
