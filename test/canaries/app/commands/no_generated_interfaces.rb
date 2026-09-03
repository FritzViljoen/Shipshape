# frozen_string_literal: true

class NoGeneratedInterfaces < Command
def call
  define_method(:x) { 1 }
end
end
