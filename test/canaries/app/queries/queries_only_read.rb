# frozen_string_literal: true

class ReadsWriteNothing < Read
def call
  CanaryRecord.create!(name: "x")
end
end
