require_relative "../test_helper"
require_relative "../../lib/acute/tool"

# Every keyword every entry point takes, found from its signature so a new option is swept the day it is added,
# fails with an Acute::Error or not at all, whatever junk it is given
class OptionSweepTest < Minitest::Test
  NOW = Time.new(2026, 10, 21, 12, 0, 0, "-04:00")
  JUNK = ["", "\xff".b.force_encoding("UTF-8"), "x" * 10_000, 10**20, -1, 0, 1.5, :nonsense, [], {}, Object.new, true].freeze

  NAMED = %i[key keyreq].freeze

  ENTRY_POINTS = {
    "parse" => [Acute.method(:parse), ->(**o) { Acute.parse("tomorrow", **o) }],
    "parse!" => [Acute.method(:parse!), ->(**o) { Acute.parse!("tomorrow", **o) }],
    "read" => [Acute.method(:read), ->(**o) { Acute.read("tomorrow", **o) }],
    "duration" => [Acute.method(:duration), ->(**o) { Acute.duration("2 hours", **o) }],
    "duration!" => [Acute.method(:duration!), ->(**o) { Acute.duration!("2 hours", **o) }],
    "extract" => [Acute.method(:extract), ->(**o) { Acute.extract("lunch tomorrow at 1", **o) }],
    "verify" => [Acute.method(:verify), ->(**o) { Acute.verify("tomorrow", "2026-10-22", **o) }],
    "describe" => [Acute.method(:describe), ->(**o) { Acute.describe(NOW + 86_400, **o) }],
    "with" => [Acute.method(:with), ->(**o) { Acute.with(**o).parse("tomorrow") }],
    "Tool.new" => [Acute::Tool.instance_method(:initialize), ->(**o) { Acute::Tool.new(**o).call("parse", { "text" => "tomorrow" }) }],
    "Duration#after" => [Acute::Duration.instance_method(:after), ->(**o) { Acute.duration("2 days").after(NOW, **o) }]
  }.freeze

  def self.keywords(method)
    params = method.parameters
    named = params.filter_map { |kind, name| name if NAMED.include?(kind) }
    params.any? { |kind, _| kind == :keyrest } ? named | keywords(Acute.method(:parse)) : named
  end

  ENTRY_POINTS.each do |name, (method, call)|
    define_method("test_#{name.tr("#!.", "___")}_options_fail_as_acute_errors") do
      keywords = self.class.keywords(method)
      refute_empty keywords
      base = { now: NOW, zone: NY }.slice(*keywords)
      failures = keywords.product(JUNK).filter_map do |option, junk|
        call.call(**base, option => junk)
        nil
      rescue Acute::Error
        nil
      rescue StandardError => e
        "#{name}(#{option}: #{junk.inspect[0, 40]}) raised #{e.class}: #{e.message[0, 100]}"
      end
      assert_empty failures, failures.join("\n")
    end
  end
end
