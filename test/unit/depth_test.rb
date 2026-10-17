require_relative "../test_helper"

# The details settled in the depth pass (D44), theme by theme
class DepthTest < Minitest::Test
  def assert_reads(text, main, alts = [], **opts)
    r = parse(text, **opts)
    assert_equal main, wall(r.begin), text
    assert_equal alts, alt_walls(r), text
  end

  def test_d40_a_weekday_with_a_time_said_on_that_day_gives_next_weeks_too
    assert_reads "saturday at 5pm", "2026-10-17 17:00:00 -04:00", ["2026-10-24 17:00:00 -04:00"]
    assert_reads "saturday 8-9pm", "2026-10-17 20:00:00 -04:00", ["2026-10-24 20:00:00 -04:00"]
  end

  def test_d40_once_todays_is_over_next_weeks_comes_first
    assert_reads "saturday morning", "2026-10-24 06:00:00 -04:00", ["2026-10-17 06:00:00 -04:00"]
    assert_reads "saturday at 9am", "2026-10-24 09:00:00 -04:00", ["2026-10-17 09:00:00 -04:00"]
  end

  def test_d40_a_day_of_the_month_said_on_that_day
    assert_reads "the 17th", "2026-10-17 00:00:00 -04:00", ["2026-11-17 00:00:00 -05:00"]
  end

  def test_d44_a_date_with_its_month_said_on_that_day_is_today_alone
    assert_reads "october 17", "2026-10-17 00:00:00 -04:00"
    assert_reads "the third saturday of the month", "2026-10-17 00:00:00 -04:00"
  end

  def test_d44_past_context_gives_the_one_before_as_well
    assert_reads "saturday", "2026-10-17 00:00:00 -04:00", ["2026-10-10 00:00:00 -04:00"], context: :past
    assert_reads "saturday at 5pm", "2026-10-10 17:00:00 -04:00", ["2026-10-17 17:00:00 -04:00"], context: :past
    assert_reads "october", "2026-10-01 00:00:00 -04:00", ["2025-10-01 00:00:00 -04:00"], context: :past
    assert_reads "Q4", "2026-10-01 00:00:00 -04:00", ["2025-10-01 00:00:00 -04:00"], context: :past
  end

  def test_d44_a_look_back_adds_no_alternative
    assert_reads "since saturday", "2026-10-17 00:00:00 -04:00"
    assert_reads "since october", "2026-10-01 00:00:00 -04:00"
  end

  def test_d3_a_season_with_a_year_starts_in_it_and_the_one_ending_in_it_is_an_alternative
    assert_reads "winter 2026", "2026-12-01 00:00:00 -05:00", ["2025-12-01 00:00:00 -05:00"]
    assert_reads "2026 winter", "2026-12-01 00:00:00 -05:00", ["2025-12-01 00:00:00 -05:00"]
    assert_reads "summer 2026", "2026-06-01 00:00:00 -04:00"
    assert_reads "summer 2026", "2026-12-01 00:00:00 +11:00", ["2025-12-01 00:00:00 +11:00"], zone: "Australia/Sydney"
    assert_reads "this winter", "2026-12-01 00:00:00 -05:00"
  end

  def assert_years(text, *spans, **opts)
    r = parse(text, **opts)
    got = [r, *r.alternatives].map { |x| [x.begin.year, x.end.year] }
    assert_equal spans, got, text
  end

  def test_d12_a_century_runs_from_its_00_year_and_the_01_reading_is_an_alternative
    assert_years "the 15th century", [1400, 1500], [1401, 1501]
    assert_years "the 3rd century A.D.", [200, 300], [201, 301]
    assert_years "this century", [2000, 2100], [2001, 2101]
    assert_years "last century", [1900, 2000], [1901, 2001]
    assert_years "next century", [2100, 2200], [2101, 2201]
  end

  def test_d12_decades_in_digits_words_and_with_the_century_left_out
    assert_years "the 1990s", [1990, 2000]
    assert_years "the 90s", [1990, 2000]
    assert_years "'90s", [1990, 2000]
    assert_years "the 20s", [2020, 2030]
    assert_years "the nineties", [1990, 2000]
    assert_years "nineteen seventies", [1970, 1980]
    assert_years "the 2000s", [2000, 2010], [2000, 2100]
  end

  def test_d12_fuzzy_decades
    r = parse("early 1990s")
    assert_equal [1990, 1994], [r.begin.year, r.end.year]
    assert_equal 1994, parse("mid-1990s").begin.year
    assert_equal 1984, parse("mid-80s").begin.year
  end

  def test_d31_last_and_next_decade_are_the_rolling_ten_years_then_the_whole_decade
    assert_reads "last decade", "2016-10-17 14:00:00 -04:00", ["2010-01-01 00:00:00 -05:00"]
    assert_reads "next decade", "2026-10-17 14:00:00 -04:00", ["2030-01-01 00:00:00 -05:00"]
    assert_reads "this decade", "2020-01-01 00:00:00 -05:00"
    assert_reads "this coming decade", "2030-01-01 00:00:00 -05:00"
  end

  def test_d44_seconds_written_like_a_decade_stay_seconds
    assert_reads "30s ago", "2026-10-17 13:59:30 -04:00"
    assert_reads "in 30s", "2026-10-17 14:00:30 -04:00"
  end

  def test_d23_an_apostrophe_marks_a_two_digit_year
    assert_reads "may '01", "2001-05-01 00:00:00 -04:00"
    assert_reads "jan 10, '00", "2000-01-10 00:00:00 -05:00"
    assert_reads "18 Sep '05", "2005-09-18 00:00:00 -04:00"
    assert_reads "halloween '11", "2011-10-31 00:00:00 -04:00"
    assert_reads "Nov '80", "1980-11-01 00:00:00 -05:00"
  end

  def assert_span(text, b, e, alts = [], **opts)
    r = parse(text, **opts)
    assert_equal [b, e], [r.begin.strftime("%F %R"), r.end.strftime("%F %R")], text
    assert_equal alts, r.alternatives.map { |x| x.begin.strftime("%F %R") }, text
  end

  def test_d44_a_bare_day_in_a_range_takes_its_month_from_the_other_end
    assert_span "from 13 to 15 July", "2027-07-13 00:00", "2027-07-16 00:00"
    assert_span "1-8 september", "2027-09-01 00:00", "2027-09-09 00:00"
    assert_span "23rd to 26th Oct", "2026-10-23 00:00", "2026-10-27 00:00"
    assert_span "between the ninth and the seventeenth of april", "2027-04-09 00:00", "2027-04-18 00:00"
    assert_span "from July 13-15", "2027-07-13 00:00", "2027-07-16 00:00"
    assert_span "4 to 22 this month", "2026-10-04 00:00", "2026-10-23 00:00"
    assert_span "5 to 9 next month", "2026-11-05 00:00", "2026-11-10 00:00"
  end

  def test_d44_a_year_said_at_the_end_of_a_range_is_the_starts_too
    assert_span "Aug 10 - Nov 12, 2013", "2013-08-10 00:00", "2013-11-13 00:00"
    assert_span "From December to May 2025", "2024-12-01 00:00", "2025-06-01 00:00"
    assert_span "10 August - 12 September 2013", "2013-08-10 00:00", "2013-09-13 00:00"
  end

  def test_d42_a_dash_with_a_space_after_a_machine_clock_is_a_range
    assert_span "2014-04-18 13:00 - 16:00", "2014-04-18 13:00", "2014-04-18 16:00"
    assert_equal "2014-04-18 18:00", parse("2014-04-18 13:00-05:00").begin.utc.strftime("%F %R")
  end

  def test_d44_a_range_of_months_or_dates_under_way_is_the_current_one_then_the_coming_one
    assert_span "from september to november", "2026-09-01 00:00", "2026-12-01 00:00", ["2027-09-01 00:00"]
    assert_span "october 1 to 20", "2026-10-01 00:00", "2026-10-21 00:00", ["2027-10-01 00:00"]
    assert_span "from october 17 to october 20", "2026-10-17 00:00", "2026-10-21 00:00"
    assert_span "march to may", "2027-03-01 00:00", "2027-06-01 00:00"
    assert_span "monday to friday", "2026-10-19 00:00", "2026-10-24 00:00"
    assert_includes codes(parse("from september to november")), :range_under_way
  end
end
