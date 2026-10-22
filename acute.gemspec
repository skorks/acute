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
  s.metadata["documentation_uri"] = "https://github.com/skorks/acute/tree/main/docs"
  files = Dir["lib/**/*.rb", "data/*.yml", "schema/**/*.json", "exe/*", "LICENSE"]
  # An untracked file under lib/ is no part of the release, so a checkout packs only what git tracks
  tracked = begin
    out = IO.popen(%w[git ls-files -z], err: File::NULL, &:read)
    out.split("\0") if Process.last_status.success?
  rescue SystemCallError
    nil
  end
  s.files = tracked ? files & tracked : files
  s.bindir = "exe"
  s.executables = ["acute"]
  s.required_ruby_version = ">= 3.3"
  s.metadata["rubygems_mfa_required"] = "true"
end
