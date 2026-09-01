# frozen_string_literal: true

class OperationsOpenNoTransaction < Command
def call
  ActiveRecord::Base.transaction { @thing.save! }
end
end
