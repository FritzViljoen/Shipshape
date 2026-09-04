# frozen_string_literal: true

class OperationsOpenNoTransaction < Deed
def call
  ActiveRecord::Base.transaction { @thing.save! }
end
end
