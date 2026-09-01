# frozen_string_literal: true

class NoNestedOperationCalls < Workflow
def call
  CreateOrder.call(composition: FindOrderComposition.call(cart_id: 1))
end
end
