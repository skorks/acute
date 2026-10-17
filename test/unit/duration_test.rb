require_relative "../test_helper"

class DurationTest < Minitest::Test
  def test_parts_as_said
    assert_equal({ hours: 1, minutes: 30 }, Acute.duration("1h30m").parts)
    assert_equal({ hours: 1, minutes: 30 }, Acute.duration("an hour and a half").parts)
    assert_equal({ minutes: 30 }, Acute.duration("half an hour").parts)
    assert_equal({ minutes: 30 }, Acute.duration("1/2 hour").parts)
    assert_equal({ weeks: 2, days: 3 }, Acute.duration("2 weeks and 3 days").parts)
    assert_equal({ days: 3, hours: 4 }, Acute.duration("3 days + 4 hours").parts)
    assert_equal({ weeks: 2 }, Acute.duration("a fortnight").parts)
    assert_equal({ business_days: 5 }, Acute.duration("5 business days").parts)
  end

  def test_a_time_is_not_a_duration
    assert_nil Acute.duration("next friday")
    assert_nil Acute.duration("tomorrow")
    assert_nil Acute.duration("")
  end

  def test_seconds_only_for_fixed_parts
    assert_equal 5400, Acute.duration("1h30m").seconds
    error = assert_raises(ArgumentError) { Acute.duration("1 month").seconds }
    assert_match(/month has no fixed length/, error.message)
  end

  def test_iso8601
    assert_equal "PT1H30M", Acute.duration("1h30m").iso8601
    assert_equal "P2W", Acute.duration("2 weeks").iso8601
    assert_equal "P17D", Acute.duration("2 weeks and 3 days").iso8601
    assert_equal "P1Y2M", Acute.duration("1 year 2 months").iso8601
    assert_equal "P3DT4H", Acute.duration("3 days + 4 hours").iso8601
    assert_nil Acute.duration("5 business days").iso8601
  end

  def test_to_s_and_to_h
    d = Acute.duration("1h30m")
    assert_equal "1h 30m", d.to_s
    assert_equal "1 hour 30 minutes", d.to_s(:long)
    assert_equal "1 year 2 months", Acute.duration("1 year 2 months").to_s(:long)
    assert_equal({ kind: "duration", parts: { hours: 1, minutes: 30 }, iso8601: "PT1H30M" }, d.to_h)
  end

  def test_equal_by_parts
    assert_equal Acute::Duration.new(minutes: 30, hours: 1), Acute.duration("1h30m")
    assert_raises(ArgumentError) { Acute::Duration.new(fortnights: 1) }
  end
end
