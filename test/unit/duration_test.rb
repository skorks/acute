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

  def test_d47_counts_in_words_past_ninety_nine
    assert_equal 205, Acute.duration("two hundred and five seconds").seconds
    assert_equal 360_000, Acute.duration("a hundred hours").seconds
  end

  def test_spoken_fractions
    assert_equal "P2Y6M", Acute.duration("two and a half years").iso8601
    assert_equal "PT5M30S", Acute.duration("5 and an half minutes").iso8601
    assert_equal "PT1H45M", Acute.duration("one and three quarters of an hour").iso8601
    assert_equal "PT1H15M", Acute.duration("an hour and a quarter").iso8601
    assert_equal "PT1H30M", Acute.duration("one hour and half").iso8601
    assert_equal "PT12H", Acute.duration("half day").iso8601
    assert_equal "PT15M", Acute.duration("a quarter of an hour").iso8601
    assert_equal "PT2M", Acute.duration("a pair of minutes").iso8601
  end

  def test_a_bare_number_after_hours_or_minutes_is_the_next_unit
    assert_equal "PT1H30M", Acute.duration("1 hour thirty").iso8601
    assert_equal "PT2H10M", Acute.duration("2 hour and 10").iso8601
    assert_equal "PT2M30S", Acute.duration("2 minutes 30").iso8601
    assert_nil Acute.duration("2 days 5")
  end

  def test_decimals_split_into_smaller_units
    assert_equal({ hours: 1, minutes: 30 }, Acute.duration("1.5 hours").parts)
    assert_equal "P3Y6M", Acute.duration("3.5years").iso8601
    assert_equal "PT10M45S", Acute.duration("10.75 minutes").iso8601
    d = Acute.duration("123.45 sec")
    assert_equal ["PT123.45S", "123.45s"], [d.iso8601, d.to_s]
    assert_equal Rational(2469, 20), d.seconds
  end

  def test_for_more_and_joined_forms
    assert_equal "P5D", Acute.duration("for 5 days").iso8601
    assert_equal "PT2M", Acute.duration("2 extra minutes").iso8601
    assert_equal "PT3M", Acute.duration("3-min").iso8601
    assert_nil Acute.duration("3 - min")
    assert_nil Acute.duration("for months")
    assert_nil Acute.duration("for")
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
    assert_equal({ kind: "duration", parts: { hours: 1, minutes: 30 }, iso8601: "PT1H30M", seconds: 5400 }, d.to_h)
    assert_equal "1 business day", Acute.duration("1 business day").to_s
    assert_equal "2 business days", Acute.duration("2 business days").to_s
  end

  def test_json
    assert_equal({ "kind" => "duration", "parts" => { "months" => 1 }, "iso8601" => "P1M", "seconds" => nil },
                 JSON.parse(Acute.duration("1 month").to_json))
    d = Acute.duration("123.45 sec")
    assert_equal({ "kind" => "duration", "parts" => { "seconds" => 123.45 }, "iso8601" => "PT123.45S", "seconds" => 123.45 },
                 d.as_json)
    assert_equal({ "business_days" => 5 }, Acute.duration("5 business days").as_json["parts"])
  end

  def test_four_digit_seconds
    assert_equal({ seconds: 5400 }, Acute.duration("5400s").parts)
    assert_equal({ seconds: 30 }, Acute.duration("30s").parts)
  end

  def test_equal_by_parts
    assert_equal Acute::Duration.new(minutes: 30, hours: 1), Acute.duration("1h30m")
    assert_raises(ArgumentError) { Acute::Duration.new(fortnights: 1) }
  end
end
