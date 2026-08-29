# frozen_string_literal: true

class NoSilentCoercion
def show
  params[:page].to_i
end
end
