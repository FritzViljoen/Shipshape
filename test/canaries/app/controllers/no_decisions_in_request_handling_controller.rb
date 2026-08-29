# frozen_string_literal: true

class NoDecisionsInRequestHandling
def show
  render :x if @canary.cancelled?
end
end
