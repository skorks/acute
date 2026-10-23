require "json"
require "yaml"
require_relative "../test_helper"
require_relative "../../lib/acute/chronic_duration"

# chronic_duration 0.10.6's and gitlab_chronic_duration 0.12.0's answers, recorded by test/chronic_duration/record.rb,
# against acute's; where it matches neither, the cause is in test/chronic_duration/differences.yml (D46)
class ChronicDurationDifferencesTest < Minitest::Test
  DIR = File.expand_path("../chronic_duration", __dir__)
  FIXTURE = File.readlines(File.join(DIR, "fixture.jsonl")).map { JSON.parse(_1) }
  DIFFERENCES = YAML.load_file(File.join(DIR, "differences.yml")).flat_map { _1["cases"] }

  def answer(method, input, opts)
    o = opts.transform_keys(&:to_sym)
    o[:format] = o[:format].to_sym if o[:format]
    ChronicDuration.raise_exceptions = o.delete(:raise_exceptions)
    JSON.parse(JSON.generate(ChronicDuration.public_send(method, input, o)))
  rescue StandardError => e
    { "error" => e.class.name }
  ensure
    ChronicDuration.raise_exceptions = false
  end

  def test_answers_as_either_gem_does_but_where_listed
    listed = DIFFERENCES.to_h { |method, input, opts, *| [[method, input, opts], true] }
    unlisted = FIXTURE.filter_map do |method, input, opts, old, new|
      got = answer(method, input, opts)
      [method, input, opts, old, new, got] if got != old && got != new && !listed.key?([method, input, opts])
    end
    assert_empty unlisted.map { JSON.generate(_1) }, "acute differs from both gems; fix it or list it with its cause"
  end

  def test_each_listed_difference_still_differs
    recorded = FIXTURE.to_h { |method, input, opts, old, new| [[method, input, opts], [old, new]] }
    stale = DIFFERENCES.reject do |method, input, opts, old, new, got|
      recorded[[method, input, opts]] == [old, new] && answer(method, input, opts) == got && got != old && got != new
    end
    assert_empty stale.map { JSON.generate(_1) }, "these no longer differ as listed; update or drop them"
  end
end
