# frozen_string_literal: true

class NoUnparsedLookup
def show
  CanaryRecord.find(params[:id])
end
end
