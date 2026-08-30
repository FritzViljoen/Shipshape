# frozen_string_literal: true

class WorkflowsBranchOnOutcome < Workflow
def call
  charge = ChargeCard.call

  success(1) if charge.value.total > 100
end
end
