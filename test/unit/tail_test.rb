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

  def test_d48_two_padded_numbers_before_a_time_are_a_date
    assert_equal "2027-05-06 12:00:00", at("05-06 at noon")
  end

  def test_d48_the_nth_day_of_a_month_is_that_date
    assert_equal "2011-11-29", day("Tuesday, the 29th day of November, 2011")
  end

  def test_d48_a_dotted_clock_where_no_date_fits
    assert_equal "2026-10-17 18:20:00", at("18.20")
    assert_equal "2026-10-16 09:30:00", at("last fri 9.30")
  end

  def test_d48_of_before_a_relative_year
    assert_equal "2027-03-01", day("March of next year")
  end

  def test_d48_last_weekday_this_month_is_the_last_of_the_month
    assert_equal "2026-10-27", day("last tuesday this month")
  end

  def test_d48_in_the_month_reads_as_of_the_month
    assert_equal "2026-11-02", day("first monday in the month")
  end

  def test_d48_this_day_in_a_year_is_todays_date_then
    assert_equal "1800-10-17", day("this day 1800")
  end

  def test_d48_a_clock_glued_to_a_date
    assert_equal "2024-05-31 14:15:00", at("05/31/2024.14:15")
    assert_equal "2024-05-31 14:15:00", at("05/31/2024:14:15")
  end

  def test_d48_brackets_around_a_word_are_dropped
    assert_equal "2014-09-04", day("[Sept] 04, 2014.")
  end

  def test_d48_a_meridiem_before_the_clock_after_a_date
    assert_equal "2020-10-09 14:26:00", at("2020/10/9 PM 2:26")
    assert_equal "2020-10-09 02:26:00", at("2020/10/9 AM 02:26")
  end

  def test_d48_a_day_before_a_dotted_date_is_a_day_of_its_month
    r = parse("12.-14.06.2021")
    assert_equal ["2021-06-12", "2021-06-15"], [r.begin.strftime("%F"), r.end.strftime("%F")]
  end

  def test_d48_fractions_of_a_second
    assert_equal 502, parse("2003-09-25T10:49:41,502").begin.strftime("%L").to_i
    assert_equal 500, parse("20030925T104941.5").begin.strftime("%L").to_i
  end

  def test_d48_a_dot_between_day_and_year
    assert_equal "2003-09-25", day("Sep.25.2003")
  end

  def test_d48_the_and_a_bare_number_is_a_day_of_the_month
    assert_equal "2026-10-24", day("the 24")
    assert_equal "2026-11-03", day("the 3 of next month")
  end

  def test_d48_a_short_year_and_quarter
    r = parse("18q4")
    assert_equal ["2018-10-01", :quarter], [r.begin.strftime("%F"), r.grain]
  end

  def test_d48_nth_last_counts_from_the_end
    assert_equal "2027-05-27", day("the fifth last day of may")
    assert_equal "2026-10-23", day("second last friday of october")
    assert_equal "2026-10-30", day("second last day of the month")
  end

  def test_d48_three_digits_after_year_are_the_year
    assert_equal "0247-01-01", day("year 247")
  end

  def test_d48_last_and_a_numeric_date_is_its_latest
    assert_equal "2026-09-11", day("last 9/11")
  end

  def test_d48_a_length_after_a_date_is_not_a_shift
    assert_nil Acute.parse("2004-05-05 12:00:00 CEST 6 months", now: "2026-10-17T14:00", zone: NY)
  end

  def span(text, **opts)
    r = parse(text, **opts)
    [r.begin&.strftime("%F %R"), r.end&.strftime("%F %R")]
  end

  def test_d48_this_last_is_this_past
    assert_equal ["2026-10-17 13:00", "2026-10-17 14:00"], span("this last hour")
  end

  def test_d48_the_working_week_is_monday_to_friday
    assert_equal ["2026-10-19 00:00", "2026-10-24 00:00"], span("next working week")
    assert_equal span("last working week"), span("monday to friday last week")
  end

  def test_d48_before_or_after_a_clock_clips_a_day
    assert_equal ["2026-10-18 00:00", "2026-10-18 16:00"], span("tomorrow before 4pm")
    assert_equal ["2026-10-18 16:00", "2026-10-19 00:00"], span("tomorrow after 4pm")
    assert_equal ["2026-10-20 14:00", "2026-10-21 00:00"], span("Tuesday of next week after 2pm")
  end

  def test_d48_for_and_during_before_a_time_are_dropped
    assert_equal "2026-09-17 14:00", span("for the past month")[0]
    assert_equal "2027-03-01", day("during March")
    assert_equal "15:15", clock("for a quarter past 3pm")
    assert_equal "2026-10-24 09:00", span("on Saturday for 9am")[0]
  end

  def test_d48_from_a_time_for_a_length_lasts_that_long
    assert_equal ["2026-12-18 00:00", "2026-12-28 00:00"], span("from 18th Dec for 10 days")
    assert_equal ["2026-10-17 16:00", "2026-10-17 16:30"], span("from 4pm for thirty minutes")
  end

  def test_d48_an_iso_interval_with_a_slash
    r = parse("2007-03-01T13:00:00Z/2008-05-11T15:30:00Z")
    assert_equal [Time.utc(2007, 3, 1, 13), Time.utc(2008, 5, 11, 15, 30)], [r.begin.utc, r.end.utc]
  end

  def test_d48_up_to_and_in_between_are_ranges
    assert_equal span("monday to friday"), span("monday up to friday")
    assert_equal ["2026-10-18 13:00", "2026-10-18 14:30"], span("tomorrow in between 1-2:30 ish")
  end

  def test_d48_all_and_the_rest_of_a_period
    assert_equal span("this week"), span("all week")
    assert_equal ["2026-10-17 14:00", "2026-10-18 00:00"], span("rest of the week")
  end

  def test_d48_anytime_before_an_open_end_is_dropped
    assert_equal ["2015-01-01 00:00", nil], span("anytime after 2014")
    assert_equal [nil, "2014-01-01 00:00"], span("sometimes before 2014")
  end

  def test_d48_around_after_beginning_of_is_approximate
    r = parse("beginning of around next week")
    assert_equal "2026-10-18", r.begin.strftime("%F")
    assert_includes r.assumptions.map(&:code), :approximate
  end

  def test_d48_today_and_tomorrow_is_both_days
    assert_equal ["2026-10-17 00:00", "2026-10-19 00:00"], span("today and tomorrow")
  end

  def test_d48_first_to_last_day_of_a_period_is_the_period
    assert_equal ["2008-01-01 00:00", "2009-01-01 00:00"], span("first to last day of 2008")
  end

  def test_d48_week_commencing
    assert_equal ["2027-02-04 00:00", "2027-02-11 00:00"], span("w/c feb 4")
  end

  def test_d48_a_clock_range_of_a_date
    assert_equal ["2027-04-22 17:00", "2027-04-22 18:00"], span("from 5 to 6pm of April 22")
    assert_equal ["2027-06-04 09:30", "2027-06-04 16:30"], span("6/4 between 9.30-4.30pm")
  end

  def test_d48_and_after_is_or_after
    assert_equal ["2016-01-01 00:00", nil], span("1/1/2016 and after")
  end

  def test_d48_after_several_lengths_is_a_shift
    assert_equal "2026-10-19 17:01", span("after 2 days, 3 hours and 1 minute")[0]
  end

  def test_d48_a_dash_between_a_week_and_a_weekday_labels_the_day
    assert_equal ["2026-10-05 00:00", "2026-10-06 00:00"], span("previous week - Monday")
  end
end
