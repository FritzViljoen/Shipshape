# frozen_string_literal: true

class AnonymityIsClosedDownward < Write
def anonymous_call
  OtherRead.call
end
end
