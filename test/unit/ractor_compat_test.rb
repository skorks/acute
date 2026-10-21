require_relative "../test_helper"
require_relative "../../lib/acute/chronic"
require_relative "../../lib/acute/chronic_duration"

# The compatibility layers parse with their defaults in any Ractor. Their process-wide settings
# (Chronic.time_class, ChronicDuration.hours_per_day) stay the main Ractor's, as in the originals.
class RactorCompatTest < Minitest::Test
  NOW = Time.utc(2026, 10, 17, 14)

  def in_ractor(*args, &)
    was = Warning[:experimental]
    Warning[:experimental] = false
    ractor_value(Ractor.new(*args, &))
  ensure
    Warning[:experimental] = was
  end

  def test_chronic_parses_in_a_ractor
    out = in_ractor(NOW) do |now|
      [Chronic.parse("tomorrow at 3pm", now: now).hour, Chronic.parse("next friday", now: now, context: :past).class.name,
       Chronic.parse("this is not a time", now: now)]
    end
    assert_equal [15, "Time", nil], out
  end

  def test_chronic_duration_parses_and_outputs_in_a_ractor
    out = in_ractor do
      [ChronicDuration.parse("1 hour and 30 minutes"), ChronicDuration.parse("two and a half hours"),
       ChronicDuration.output(3600), ChronicDuration.output(5400, format: :long)]
    end
    assert_equal [5400, 9000, "1 hr", "1 hour 30 minutes"], out
  end

  def test_the_constants_are_shareable
    [Chronic::Parser::DEFAULT_OPTIONS, ChronicDuration::UNITS, ChronicDuration::MAPPINGS, ChronicDuration::DIVIDERS,
     ChronicDuration.const_get(:Numerizer)::DIRECT_NUMS].each { assert Ractor.shareable?(_1) }
  end
end
