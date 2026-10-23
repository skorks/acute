require_relative "../test_helper"
require_relative "../../lib/acute/chronic_duration"

# chronic_duration 0.10.6's spec and GitLab 0.12.0's, which adds per-call hours_per_day and days_per_month; then
# where the layer differs from both gems (D46)
class ChronicDurationTest < Minitest::Test
  PARSE = {
    "1:20" => 60 + 20,
    "1:20.51" => 60 + 20.51,
    "4:01:01" => 4 * 3600 + 60 + 1,
    "3 mins 4 sec" => 3 * 60 + 4,
    "3 Mins 4 Sec" => 3 * 60 + 4,
    "three mins four sec" => 3 * 60 + 4,
    "2 hrs 20 min" => 2 * 3600 + 20 * 60,
    "2h20min" => 2 * 3600 + 20 * 60,
    "6 mos 1 day" => 6 * 30 * 24 * 3600 + 24 * 3600,
    "1 year 6 mos 1 day" => 1 * 31_557_600 + 6 * 30 * 24 * 3600 + 24 * 3600,
    "2.5 hrs" => 2.5 * 3600,
    "47 yrs 6 mos and 4.5d" => 47 * 31_557_600 + 6 * 30 * 24 * 3600 + 4.5 * 24 * 3600,
    "two hours and twenty minutes" => 2 * 3600 + 20 * 60,
    "four hours and forty minutes" => 4 * 3600 + 40 * 60,
    "four hours, and fourty minutes" => 4 * 3600 + 40 * 60,
    "3 weeks and, 2 days" => 3600 * 24 * 7 * 3 + 3600 * 24 * 2,
    "3 weeks, plus 2 days" => 3600 * 24 * 7 * 3 + 3600 * 24 * 2,
    "3 weeks with 2 days" => 3600 * 24 * 7 * 3 + 3600 * 24 * 2,
    "1 month" => 3600 * 24 * 30,
    "2 months" => 3600 * 24 * 30 * 2,
    "18 months" => 3600 * 24 * 30 * 18,
    "1 year 6 months" => (3600 * 24 * (365.25 + 6 * 30)).to_i,
    "day" => 3600 * 24,
    "minute 30s" => 90
  }.freeze

  # The spec's second 7200 entry replaced its first, so its chrono is "2:20:00"
  OUTPUT = {
    (60 + 20) => { micro: "1m20s", short: "1m 20s", default: "1 min 20 secs", long: "1 minute 20 seconds", chrono: "1:20" },
    (60 + 20.51) => { micro: "1m20.51s", short: "1m 20.51s", default: "1 min 20.51 secs", long: "1 minute 20.51 seconds",
                      chrono: "1:20.51" },
    (60 + 20.51928) => { micro: "1m20.51928s", short: "1m 20.51928s", default: "1 min 20.51928 secs",
                         long: "1 minute 20.51928 seconds", chrono: "1:20.51928" },
    (4 * 3600 + 60 + 1) => { micro: "4h1m1s", short: "4h 1m 1s", default: "4 hrs 1 min 1 sec", long: "4 hours 1 minute 1 second",
                             chrono: "4:01:01" },
    (2 * 3600 + 20 * 60) => { micro: "2h20m", short: "2h 20m", default: "2 hrs 20 mins", long: "2 hours 20 minutes",
                              chrono: "2:20:00" },
    (6 * 30 * 24 * 3600 + 24 * 3600) => { micro: "6mo1d", short: "6mo 1d", default: "6 mos 1 day", long: "6 months 1 day",
                                          chrono: "6:01:00:00:00" },
    (365.25 * 24 * 3600 + 24 * 3600).to_i => { micro: "1y1d", short: "1y 1d", default: "1 yr 1 day", long: "1 year 1 day",
                                               chrono: "1:00:01:00:00:00" },
    (3 * 365.25 * 24 * 3600 + 24 * 3600).to_i => { micro: "3y1d", short: "3y 1d", default: "3 yrs 1 day", long: "3 years 1 day",
                                                   chrono: "3:00:01:00:00:00" },
    (3600 * 24 * 30 * 18) => { micro: "18mo", short: "18mo", default: "18 mos", long: "18 months", chrono: "18:00:00:00:00" }
  }.freeze

  def teardown
    ChronicDuration.raise_exceptions = false
    ChronicDuration.hours_per_day = 24
    ChronicDuration.days_per_month = 30
  end

  def cleanup(text) = ChronicDuration.send(:cleanup, text)

  def test_parse_exemplars
    PARSE.each { |text, seconds| assert_equal seconds, ChronicDuration.parse(text), text }
  end

  def test_unparseable_and_zero_are_nil
    assert_nil ChronicDuration.parse("gobblygoo")
    assert_nil ChronicDuration.parse("0")
    assert_equal 0, ChronicDuration.parse("0", keep_zero: true)
  end

  def test_raise_exceptions
    ChronicDuration.raise_exceptions = true
    assert_raises(ChronicDuration::DurationParseError) { ChronicDuration.parse("23 gobblygoos") }
    ChronicDuration.raise_exceptions = "yes"
    assert_same true, ChronicDuration.raise_exceptions
  end

  def test_floats_only_for_decimal_seconds
    assert_kind_of Float, ChronicDuration.parse("12 mins 3.141 seconds")
    assert_kind_of Integer, ChronicDuration.parse("12 mins 3 seconds")
  end

  def test_default_unit
    assert_equal 300, ChronicDuration.parse("5", default_unit: "minutes")
  end

  def test_parse_with_hours_per_day_and_days_per_month
    assert_equal 24 * 60 * 60, ChronicDuration.parse("1d", hours_per_day: 24)
    assert_equal 8 * 60 * 60, ChronicDuration.parse("1d", hours_per_day: 8)
    assert_equal 30 * 24 * 60 * 60, ChronicDuration.parse("1mo", days_per_month: 30)
    assert_equal 20 * 24 * 60 * 60, ChronicDuration.parse("1mo", days_per_month: 20)
    assert_equal 7 * 24 * 60 * 60, ChronicDuration.parse("1w", days_per_month: 30)
    assert_equal 5 * 24 * 60 * 60, ChronicDuration.parse("1w", days_per_month: 20)
    assert_equal 30 * 24 * 60 * 60, ChronicDuration.parse("1mo", days_per_month: 30, hours_per_day: 24)
    assert_equal 20 * 8 * 60 * 60, ChronicDuration.parse("1mo", days_per_month: 20, hours_per_day: 8)
    assert_equal 7 * 24 * 60 * 60, ChronicDuration.parse("1w", days_per_month: 30, hours_per_day: 24)
    assert_equal 5 * 8 * 60 * 60, ChronicDuration.parse("1w", days_per_month: 20, hours_per_day: 8)
  end

  def test_output_exemplars
    OUTPUT.each do |seconds, formats|
      formats.each { |format, text| assert_equal text, ChronicDuration.output(seconds, format: format), "#{seconds} #{format}" }
    end
  end

  def test_output_keep_zero
    { micro: "0s", short: "0s", default: "0 secs", long: "0 seconds", chrono: "0" }.each do |format, text|
      assert_equal text, ChronicDuration.output(0, format: format, keep_zero: true), format
    end
    %i[micro short default long].each { |format| assert_nil ChronicDuration.output(0, format: format, keep_zero: false) }
    assert_equal "0", ChronicDuration.output(0, format: :chrono, keep_zero: false)
  end

  def test_output_weeks_and_limit_to_hours
    assert_match(/.*wk.*/, ChronicDuration.output(45 * 24 * 60 * 60, weeks: true))
    assert_equal "9480 hrs 15 mins", ChronicDuration.output(395 * 24 * 60 * 60 + 15 * 60, limit_to_hours: true)
  end

  def test_output_with_hours_per_day_and_days_per_month
    assert_equal "1 day", ChronicDuration.output(24 * 60 * 60, hours_per_day: 24)
    assert_equal "3 days", ChronicDuration.output(24 * 60 * 60, hours_per_day: 8)
    assert_equal "1 wk", ChronicDuration.output(7 * 24 * 60 * 60, weeks: true, days_per_month: 30)
    assert_equal "1 wk 2 days", ChronicDuration.output(7 * 24 * 60 * 60, weeks: true, days_per_month: 20)
    assert_equal "1 wk", ChronicDuration.output(7 * 24 * 60 * 60, weeks: true, days_per_month: 30, hours_per_day: 24)
    assert_equal "1 wk", ChronicDuration.output(5 * 8 * 60 * 60, weeks: true, days_per_month: 20, hours_per_day: 8)
    assert_equal "1 mo", ChronicDuration.output(30 * 24 * 60 * 60, days_per_month: 30, hours_per_day: 24)
    assert_equal "1 mo 2 days", ChronicDuration.output(30 * 24 * 60 * 60, days_per_month: 30, hours_per_day: 24, weeks: true)
    assert_equal "1 mo", ChronicDuration.output(20 * 8 * 60 * 60, days_per_month: 20, hours_per_day: 8)
    assert_equal "1 mo", ChronicDuration.output(20 * 8 * 60 * 60, days_per_month: 20, hours_per_day: 8, weeks: true)
  end

  def test_output_units_and_joiner
    assert_equal "4 hrs 1 min", ChronicDuration.output(4 * 3600 + 60 + 1, units: 2)
    assert_equal "6 months 1 day 1 hour", ChronicDuration.output(6 * 30 * 24 * 3600 + 24 * 3600 + 3600 + 60 + 1, units: 3, format: :long)
    assert_equal "2 hrs 20 mins", ChronicDuration.output(2 * 3600 + 20 * 60)
    assert_equal "2 hrs, 20 mins", ChronicDuration.output(2 * 3600 + 20 * 60, joiner: ", ")
  end

  def test_chrono_output_round_trips_from_a_second_to_over_a_century
    [1, 59, 60, 61, 3599, 3600, 86_399, 86_400, 604_800, 2_592_000, 31_557_600, 100 * 31_557_600 + 3 * 86_400 + 7, 123 * 31_557_600 + 1, 80.51].each do |n|
      assert_equal n, ChronicDuration.parse(ChronicDuration.output(n, format: :chrono)), n.to_s
    end
  end

  def test_output_parses_back
    OUTPUT.each do |seconds, formats|
      formats.each_key { |format| assert_equal seconds, ChronicDuration.parse(ChronicDuration.output(seconds, format: format)), "#{seconds} #{format}" }
    end
  end

  # 0.10.6 sets the week's days; 0.12.0 the month's, a week being a quarter of it
  def test_work_week
    ChronicDuration.hours_per_day = 8
    ChronicDuration.days_per_week = 5
    week = ChronicDuration.parse("5d")
    assert_equal [week, week], [ChronicDuration.parse("40h"), ChronicDuration.parse("1w")]
    ChronicDuration.days_per_week = 7
    ChronicDuration.days_per_month = 20
    assert_equal [week, week], [ChronicDuration.parse("40h"), ChronicDuration.parse("1w")]
    assert_equal 5, ChronicDuration.days_per_week
  end

  def test_d46_words_the_gems_skip_take_acutes_reading_at_their_lengths
    { "half an hour" => 1800, "half hour" => 1800, "an hour and a half" => 5400, "1/2 hour" => 1800,
      "three quarters of an hour" => 2700, "a couple of days" => 172_800, "1 fortnight" => 1_209_600,
      "1 decade" => 315_576_000, "5 mins." => 300 }.each { |text, seconds| assert_equal seconds, ChronicDuration.parse(text), text }
    assert_equal 2.5 * 5 * 8 * 3600, ChronicDuration.parse("2.5 weeks plus", hours_per_day: 8, days_per_month: 20)
    assert_equal 3 * 86_400, ChronicDuration.parse("3 business days")
    assert_equal 10_800, ChronicDuration.parse("about 3 hours")
  end

  def test_d47_text_acute_refuses_gets_the_gems_reading
    assert_equal 18_000, ChronicDuration.parse("1. 5 hours")
    assert_equal 522_000, ChronicDuration.parse("half145h")
  end

  def test_d46_raise_exceptions_only_for_text_acute_cannot_read_either
    ChronicDuration.raise_exceptions = true
    assert_equal 3600, ChronicDuration.parse("an hour")
    assert_equal 7200, ChronicDuration.parse("for 2 hours")
    error = assert_raises(ChronicDuration::DurationParseError) { ChronicDuration.parse("about 3 hours") }
    assert_equal 'An invalid word "about" was used in the string to be parsed.', error.message
  end

  def test_d46_a_clock_group_counts_wherever_it_stands
    assert_equal 2 * 86_400 + 4 * 3600 + 13 * 60 + 2, ChronicDuration.parse("2 days, 4:13:02")
    assert_equal 4 * 86_400 + 3 * 60 + 15, ChronicDuration.parse("4 days 3:15")
    assert_equal 7200, ChronicDuration.parse("Duration: 2 hours")
    assert_equal 20, ChronicDuration.parse("1 : 20")
    assert_nil ChronicDuration.parse("1:2:3:4:5:6:7")
  end

  def test_d46_chrono_with_weeks_and_frozen_options
    assert_equal "4:01:01", ChronicDuration.output(4 * 3600 + 60 + 1, format: :chrono, weeks: true)
    opts = { units: 1 }.freeze
    assert_equal "4 hrs", ChronicDuration.output(4 * 3600 + 60 + 1, opts)
    assert_equal 300, ChronicDuration.parse("5", { default_unit: "minutes" }.freeze)
  end
end
