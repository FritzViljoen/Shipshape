# frozen_string_literal: true

class AggregationIsReadable < Workflow
def call
  SomeCommand.call
end
end
