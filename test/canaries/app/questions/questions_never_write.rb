# frozen_string_literal: true

class QuestionsNeverWrite < Question
def call
  CanaryRecord.create!(name: "x")
end
end
