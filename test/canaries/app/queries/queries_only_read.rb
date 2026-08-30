# frozen_string_literal: true

class QueriesOnlyRead < Query
def call
  CanaryRecord.create!(name: "x")
end
end
