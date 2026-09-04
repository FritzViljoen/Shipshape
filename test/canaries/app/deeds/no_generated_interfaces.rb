# frozen_string_literal: true

class NoGeneratedInterfaces < Deed
def call
  define_method(:x) { 1 }
end
end
