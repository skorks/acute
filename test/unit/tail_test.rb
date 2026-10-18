require_relative "../test_helper"

# The details settled in the tail pass (D48)
class TailTest < Minitest::Test
  def day(text, **opts) = parse(text, **opts).begin.strftime("%F")

  def test_d48_a_possessive_reads_as_the_word
    assert_equal "2026-10-18", day("tomorrow's")
    assert_equal "2026-10-17", day("todays")
    assert_equal "2026-10-04", day("last week's sunday")
    assert_equal "2026-06-01", day("this year's summer")
  end

  def test_d48_a_weekday_from_a_week_is_the_weekday_of_it
    assert_equal day("sunday of last week"), day("sunday from last week")
  end

  def test_d48_calendar_before_a_unit_is_the_unit
    assert_equal "2008-01-01", day("calendar year 2008")
    assert_equal "2026-11-01", day("next calendar month")
  end

  def test_d48_out_after_a_length_is_hence
    assert_equal "2026-10-17 14:15", parse("15 minute out").begin.strftime("%F %R")
  end

  def test_d48_deliberately_unread
    assert_nil Acute.parse("ATM", now: "2026-10-17T14:00", zone: NY)
    assert_nil Acute.parse("in 1 mon", now: "2026-10-17T14:00", zone: NY)
    assert_nil Acute.parse("twenty and four hours", now: "2026-10-17T14:00", zone: NY)
  end

  def clock(text, **opts) = parse(text, **opts).begin.strftime("%R")

  def test_d48_ish_between_a_number_and_its_meridiem
    assert_equal "15:00", clock("3ish pm")
    assert_includes parse("3ish pm").assumptions.map(&:code), :approximate
  end

  def test_d48_a_24_hour_clock_before_hours_is_the_clock
    assert_equal "06:00", clock("06:00 hours")
    assert_equal "18:30", clock("18:30 hours")
    assert_nil Acute.parse("1:30 hours", now: "2026-10-17T14:00", zone: NY)
  end

  def test_d48_half_an_hour_is_half_past_it
    assert_equal "15:30", clock("half three")
    assert_equal "15:30", clock("half 3")
  end

  def test_d48_minutes_to_a_clock_with_its_minutes
    assert_equal "17:27", clock("three mins to five thirty")
    assert_equal "11:40", clock("twenty to twelve")
  end

  def at(text, **opts) = parse(text, **opts).begin.strftime("%F %T")

  def test_d48_prime_notation_is_minutes_and_seconds
    assert_equal "2026-10-17 14:02:00", at("in 2'")
    assert_equal "2026-10-17 14:00:01", at("in 1\"")
    assert_equal "PT2M", Acute.duration("2'").iso8601
    assert_equal ["2015-05-01"], Acute.extract("'TUNNEL 64' 2015-05-01", now: "2026-10-17T14:00", zone: NY).mentions.map(&:text)
  end

  def test_d48_the_half_sign_is_half
    assert_equal "PT30M", Acute.duration("½ hour").iso8601
  end

  def test_d48_a_season_as_a_unit_runs_three_months_from_december_march_june_or_september
    assert_equal "2026-09-01", day("this season")
    assert_equal "2026-06-01", day("last season")
    assert_equal "2026-12-01", day("next season")
    assert_equal "2024-06-01", day("three summers ago")
  end

  def test_d48_a_bare_hundred_is_a_hundred
    assert_equal "P1000Y", Acute.duration("hundred decades").iso8601
    assert_raises(Acute::ParseError) { parse("two thousand three thousand days ago") }
  end

  def test_d48_leap_day_and_leap_year_are_named_like_holidays
    assert_equal "2028-01-01", day("next leap year")
    assert_equal :year, parse("next leap year").grain
    assert_equal "2028-02-29", day("next leap day")
    assert_equal "2024-01-01", day("last leap year")
    assert_raises(Acute::ParseError) { parse("leap day 2027") }
  end

  def test_d48_a_buddhist_era_year_is_543_years_ahead
    assert_equal "2012-08-10", day("August 10 2555 BE")
    assert_equal "2012-01-01", day("2555 BE")
    assert_raises(Acute::ParseError) { parse("march 2025 be") }
  end

  def test_d48_the_nth_closest_is_counted_by_distance_either_side
    opts = { now: "2013-02-12T04:30" }
    assert_equal "2013-10-07", day("the closest monday to oct 5th", **opts)
    assert_equal "2013-09-30", day("the second closest mon to october fifth", **opts)
    assert_equal "2012-12-25", day("the closest xmas to today", **opts)
    assert_equal "2013-12-25", day("the second closest xmas to today", **opts)
    assert_equal "2011-12-25", day("the 3rd closest xmas to today", **opts)
    assert_equal "2013-10-07", day("the nearest monday to oct 5th", **opts)
  end
end
