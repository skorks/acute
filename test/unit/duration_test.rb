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

  def test_d47_no_spaced_decimals_or_counted_halves
    assert_nil Acute.duration("1. 5 hours")
    assert_nil Acute.duration("half145h")
    assert_nil Acute.duration("half 3 hours")
    assert_equal 5400, Acute.duration("1.5 hours").seconds
    assert_equal 43_200, Acute.duration("half a day").seconds
    assert_equal 1800, Acute.duration("half hour").seconds
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

  # D52
  def test_d52_iso8601_reads_back
    durations = [
      {}, { hours: 1, minutes: 30 }, { weeks: 2 }, { years: 1, months: 2, days: 3, hours: 4, minutes: 5, seconds: 6 },
      { months: 18 }, { seconds: Rational(1, 2) }, { minutes: 1, seconds: Rational(12_345, 100) }, { seconds: Rational(1, 100_000) },
      { days: 1, hours: 12 }, { seconds: 10**12 }, { days: -3 }, { hours: -2, minutes: 30 }, { seconds: Rational(-1, 4) }
    ].map { Acute::Duration.new(**_1) }
    durations += ["1h30m", "2 weeks", "two and a half years", "123.45 sec", "3 days + 4 hours", "half an hour"].map { Acute.duration(_1) }
    durations.each { |d| assert_equal d, Acute.duration(d.iso8601), d.iso8601 }
  end

  def test_d52_extract_finds_an_iso_duration_as_a_length
    found = Acute.extract("it took PT1H30M, then P2W tomorrow").mentions.map { [_1.text, _1.kind] }
    assert_equal [["PT1H30M", :duration], ["P2W", :duration], ["tomorrow", :time]], found
    assert_nil Acute.duration("PT1H 30 minutes")
  end

  def test_d52_weeks_beside_days_read_back_as_days
    d = Acute::Duration.new(weeks: 2, days: 3)
    assert_equal "P17D", d.iso8601
    assert_equal({ days: 17 }, Acute.duration(d.iso8601).parts)
  end

  def test_d52_fraction_of_a_second_is_written_without_an_exponent
    assert_equal "PT0.00001S", Acute::Duration.new(seconds: Rational(1, 100_000)).iso8601
    assert_equal "-0.000015s", Acute::Duration.new(seconds: Rational(-15, 1_000_000)).to_s
  end

  def test_d52_iso8601_forms
    {
      "PT1H30M" => { hours: 1, minutes: 30 }, "P1Y2M3DT4H5M6S" => { years: 1, months: 2, days: 3, hours: 4, minutes: 5, seconds: 6 },
      "P2W" => { weeks: 2 }, "PT0.5S" => { seconds: Rational(1, 2) }, "PT0,5S" => { seconds: Rational(1, 2) },
      "P1DT12H" => { days: 1, hours: 12 }, "p1dt12h" => { days: 1, hours: 12 }, "pt1h30m" => { hours: 1, minutes: 30 },
      "P1M" => { months: 1 }, "PT1M" => { minutes: 1 }, "P1.5Y" => { years: 1, months: 6 }, "PT1.5H" => { hours: 1, minutes: 30 },
      "P1W2D" => { weeks: 1, days: 2 }, "P0D" => {}, "PT0S" => {}, "P0Y1D" => { days: 1 }, "-P1DT2H" => { days: -1, hours: -2 },
      "P-1D" => { days: -1 }, " PT45M " => { minutes: 45 }
    }.each { |text, parts| assert_equal parts, Acute.duration(text)&.parts, text }
  end

  def test_d52_bad_iso8601_forms
    ["P", "PT", "P1H", "PT1D", "P1.5Y2M", "PT1.5H30M", "P1D1Y", "PT1S1M", "P1DT", "P1D2D", "PT.5S", "PT1.S", "P1", "PT1H30",
     "P1Dx", "P1D5", "PT1H-", "P--1D", "P1DT1H 2M", "1P1D", "P1D/P2D", "PT1234567890123456789S"].each do |text|
      assert_nil Acute.duration(text), text
    end
    assert_nil Acute.parse("PT1H30M")
    assert_nil Acute.parse("P2W")
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

  NOW = Time.new(2026, 10, 17, 14, 0, 0, "-04:00")

  def after(text, time = NOW, **opts) = wall(Acute.duration(text).after(time, zone: NY, **opts))

  def test_d47_after_reads_as_from_that_time
    assert_equal "2026-10-31 14:00:00 -04:00", after("2 weeks")
    assert_equal "2026-10-21 14:00:00 -04:00", after("3 business days")
    assert_equal "2026-10-17 15:30:00 -04:00", after("1h30m")
    assert_equal "2027-02-28 00:00:00 -05:00", after("1 month", Time.new(2027, 1, 31, 0, 0, 0, "-05:00"))
    assert_equal wall(parse("1 year 2 months 3 days 4 hours from now").time), after("1 year 2 months 3 days 4 hours")
  end

  def test_d47_after_keeps_the_wall_clock_for_days_and_elapsed_time_for_hours
    fall_back = Time.new(2026, 10, 31, 12, 0, 0, "-04:00")
    assert_equal "2026-11-01 12:00:00 -05:00", after("1 day", fall_back)
    assert_equal "2026-11-01 11:00:00 -05:00", after("24 hours", fall_back)
  end

  def test_d47_after_keeps_fractions_of_a_second
    t = Acute.duration("123.45 seconds").after(NOW + Rational(1, 10), zone: NY)
    assert_equal NOW + Rational(12_355, 100), t
    assert_equal NOW, Acute::Duration.new(seconds: 0).after(NOW, zone: NY)
  end

  def test_d47_seconds_from_a_time
    assert_equal 2_419_200, Acute.duration("1 month").seconds(from: Time.new(2027, 2, 1, 0, 0, 0, "-05:00"), zone: NY)
    assert_equal 2_678_400, Acute.duration("1 month").seconds(from: Time.new(2027, 1, 1, 0, 0, 0, "-05:00"), zone: NY)
    assert_equal 90_000, Acute.duration("1 day").seconds(from: Time.new(2026, 10, 31, 12, 0, 0, "-04:00"), zone: NY)
    assert_raises(ArgumentError) { Acute.duration("1 month").seconds }
  end

  def test_d47_duration_bang_raises_what_duration_returns_nil_for
    assert_equal Acute.duration("90 min"), Acute.duration!("90 min")
    e = assert_raises(Acute::ParseError) { Acute.duration!("3 bananas") }
    assert_equal :unknown_word, e.code
    e = assert_raises(Acute::ParseError) { Acute.duration!("next friday") }
    assert_equal :conflict, e.code
    assert_equal :too_long, assert_raises(Acute::ParseError) { Acute.duration!("1 hour " * 200) }.code
    assert_raises(ArgumentError) { Acute.duration!(5) }
  end

  def test_equal_by_parts
    assert_equal Acute::Duration.new(minutes: 30, hours: 1), Acute.duration("1h30m")
    assert_raises(ArgumentError) { Acute::Duration.new(fortnights: 1) }
  end
end
