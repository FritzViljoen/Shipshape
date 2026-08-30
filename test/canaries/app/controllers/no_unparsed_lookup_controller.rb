# frozen_string_literal: true

class NoUnparsedLookup < ApplicationController
def show
  CanaryRecord.find(params[:id])
end
end
