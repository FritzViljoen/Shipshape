# frozen_string_literal: true

class NoInlineParamParse < ApplicationController
def show
  Date.parse(params[:on])
end
end
