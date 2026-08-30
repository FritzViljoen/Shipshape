# frozen_string_literal: true

class NoSilentCoercion < ApplicationController
def show
  params[:page].to_i
end
end
