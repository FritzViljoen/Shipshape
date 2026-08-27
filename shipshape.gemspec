# frozen_string_literal: true

require_relative "lib/shipshape/version"

Gem::Specification.new do |spec|
  spec.name = "shipshape"
  spec.version = Shipshape::VERSION
  spec.authors = ["Fritz Viljoen"]
  spec.summary = "A canon for Rails codebases, and the guards that hold it."
  spec.description = <<~TEXT
    Gives every kind of code a place and keeps it there. Cops for operation shape,
    a baseline derived from version control rather than a checked-in file, and the
    rules delivered to agents as well as to CI.
  TEXT
  spec.homepage = "https://github.com/FritzViljoen/shipshape"
  spec.license = "MIT"

  # Spans the two intended consumers. Nothing here may use pattern matching,
  # Data.define, or endless methods.
  spec.required_ruby_version = ">= 2.7.0"

  spec.files = Dir["lib/**/*.rb", "lib/**/*.tt", "config/**/*.yml", "docs/**/*.md", "README.md", "exe/*"]
  spec.bindir = "exe"
  spec.executables = ["shipshape"]
  spec.require_paths = ["lib"]

  spec.add_dependency "rubocop", ">= 1.0"

  spec.metadata["rubygems_mfa_required"] = "true"
end
