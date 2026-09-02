# frozen_string_literal: true

class OperationsOpenNoTransaction < Write
def call
  ActiveRecord::Base.transaction { @thing.save! }
end
end
