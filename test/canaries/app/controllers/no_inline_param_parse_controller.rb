# frozen_string_literal: true

class NoInlineParamParse
def show
  Date.parse(params[:on])
end
end
