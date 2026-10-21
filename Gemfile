source "https://rubygems.org"

gemspec

# A gemspec can't declare a platform-only dependency, so Windows (no system zoneinfo) gets its zone data here
gem "tzinfo-data", platforms: :windows

group :development do
  gem "benchmark"
  gem "minitest"
  gem "rubocop", "1.92.0", require: false
  gem "rubocop-minitest", "0.41.0", require: false
  gem "rubocop-performance", "1.27.0", require: false
  gem "ruby_llm", "2.1.1", require: false
end
