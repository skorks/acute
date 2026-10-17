source "https://rubygems.org"

gemspec

# A gemspec can't declare a platform-only dependency, so Windows (no system zoneinfo) gets its zone data here
gem "tzinfo-data", platforms: :windows

group :development do
  gem "minitest"
  gem "benchmark"
end
