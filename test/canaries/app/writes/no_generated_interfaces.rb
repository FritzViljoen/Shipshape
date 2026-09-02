# frozen_string_literal: true

class NoGeneratedInterfaces < Write
def call
  define_method(:x) { 1 }
end
end
