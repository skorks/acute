require_relative "lib/acute/version"

Gem::Specification.new do |s|
  s.name = "acute"
  s.version = Acute::VERSION
  s.summary = "Plain-English date and time parsing, a successor to chronic"
  s.authors = ["Alan Skorkin"]
  s.license = "MIT"
  s.homepage = "https://github.com/skorks/acute"
  s.metadata["source_code_uri"] = "https://github.com/skorks/acute"
  s.metadata["changelog_uri"] = "https://github.com/skorks/acute/blob/main/CHANGELOG.md"
  s.metadata["bug_tracker_uri"] = "https://github.com/skorks/acute/issues"
  s.files = Dir["lib/**/*.rb", "data/*.yml", "schema/*.json", "exe/*", "LICENSE"]
  s.bindir = "exe"
  s.executables = ["acute"]
  s.required_ruby_version = ">= 3.3"
  s.add_dependency "tzinfo", "~> 2.0", ">= 2.0.5"
  s.metadata["rubygems_mfa_required"] = "true"
end
