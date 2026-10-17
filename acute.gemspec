require_relative "lib/acute/version"

Gem::Specification.new do |s|
  s.name = "acute"
  s.version = Acute::VERSION
  s.summary = "Plain-English date and time parsing, a successor to chronic"
  s.authors = ["Alan Skorkin"]
  s.license = "MIT"
  s.files = Dir["lib/**/*.rb", "data/*.yml"]
  s.required_ruby_version = ">= 3.3"
  s.add_dependency "tzinfo", "~> 2.0"
end
