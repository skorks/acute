require_relative "../test_helper"

# More of the details settled in the depth pass (D44)
class DepthMoreTest < Minitest::Test
  def span(text, **opts)
    r = parse(text, **opts)
    [r.begin && wall(r.begin), r.end && wall(r.end)]
  end

  def test_d44_two_dotted_numbers_after_at_are_a_clock
    assert_equal "2026-10-18 12:30:00 -04:00", wall(parse("at 12.30").begin)
    assert_equal "2026-12-30 00:00:00 -05:00", wall(parse("12.30").begin)
    assert_raises(Acute::ParseError) { parse("at 650.650.6500") }
  end

  def test_d44_a_clock_joined_to_a_numeric_date_by_a_dash_is_its_time
    assert_equal "2024-05-31 14:15:00 -04:00", wall(parse("05/31/2024-14:15").begin)
    assert_equal ["2024-05-31 00:00:00 -04:00", "2024-05-31 14:15:00 -04:00"], span("05/31/2024 - 14:15")
  end

  def test_d44_an_overnight_clock_range_begun_yesterday_is_under_way
    assert_equal ["2026-10-16 23:00:00 -04:00", "2026-10-17 15:00:00 -04:00"], span("from 23 to 3pm")
    assert_equal ["2026-10-17 23:00:00 -04:00", "2026-10-18 03:00:00 -04:00"], span("11pm to 3am")
  end

  def test_d44_looking_back_a_passed_this_month_is_the_one_passed
    assert_equal ["2026-08-01 00:00:00 -04:00", "2026-10-17 14:00:00 -04:00"], span("since this August")
  end

  def test_d44_starting_x_is_open_from_its_start
    assert_equal ["2027-01-07 00:00:00 -05:00", nil], span("starting January 7th")
    assert_equal ["2027-01-07 00:00:00 -05:00", nil], span("beginning on January 7th")
    assert_equal ["2026-10-18 00:00:00 -04:00", nil], span("starting from next week")
    assert_equal "2027-01-01 00:00:00 -05:00", wall(parse("beginning of January").begin)
  end

  def test_d44_a_count_of_units_starting_x_runs_that_long_from_its_start
    assert_equal ["2026-10-19 00:00:00 -04:00", "2026-10-22 00:00:00 -04:00"], span("3 days starting from next Monday")
    assert_equal ["2027-02-04 00:00:00 -05:00", "2027-02-11 00:00:00 -05:00"], span("the week commencing february 4")
  end

  def test_d44_two_digits_after_a_numeric_day_and_month_are_its_year
    r = parse("08/12,15")
    assert_equal ["2015-08-12 00:00:00 -04:00", :day], [wall(r.begin), r.grain]
    assert_equal "2027-08-12 15:00:00 -04:00", wall(parse("08/12 15:00").begin)
  end

  def test_d38_an_ambiguous_zone_gives_each_of_its_offsets_in_order
    r = parse("Jul 15, 2027 3:45pm IST")
    assert_equal "2027-07-15 06:15:00 -04:00", wall(r.begin)
    assert_equal ["2027-07-15 10:45:00 -04:00", "2027-07-15 09:45:00 -04:00"], alt_walls(r)
    assert_includes r.assumptions.map(&:code), :ambiguous_zone
    assert_equal ["2027-07-15 05:45:00 -04:00"], alt_walls(parse("Jul 15, 2027 3:45pm BST"))
  end

  def test_d38_bst_in_gb_is_british_summer_time_alone
    r = parse("Jul 15, 2027 3:45pm BST", zone: "Europe/London")
    assert_equal ["2027-07-15 15:45:00 +01:00", []], [wall(r.begin), alt_walls(r)]
    refute_includes r.assumptions.map(&:code), :ambiguous_zone
  end

  def test_d44_a_zone_in_brackets_is_the_zone_and_a_second_zone_labels_the_first
    assert_equal "2014-08-17 20:00:00 -04:00", wall(parse("08/17/14 17:00 (PDT)").begin)
    assert_equal "2016-09-22 22:34:51 -04:00", wall(parse("Fri Sep 23 2016 10:34:51 GMT+0800 (CST)").begin)
    assert_equal "2026-11-23 15:45:30 -05:00", wall(parse("Mon Nov 23 2026 15:45:30 GMT-0500 (Eastern Standard Time)").begin)
    assert_equal "2010-05-12 14:04:34 -04:00", wall(parse("12 May 2010 2:04:34 PM Eastern Daylight Time").begin)
    assert_raises(Acute::ParseError) { parse("9 am (tomorrow)") }
    assert_raises(Acute::ParseError) { parse("9 am (bst") }
  end

  def test_d44_a_weekday_that_fits_both_orders_picks_the_locales
    r = parse("Friday 7/6", now: "2018-07-06T12:00:00", zone: "UTC")
    assert_equal ["2018-07-06 00:00:00 +00:00", []], [wall(r.begin), alt_walls(r)]
    refute_includes r.assumptions.map(&:code), :numeric_date_order
    assert_equal "2018-06-07 00:00:00 +00:00", wall(parse("Thursday 7/6", now: "2018-07-06T12:00:00", zone: "UTC").begin)
  end

  def test_d6_a_range_ending_at_midnight_today_ends_at_its_end_then_its_start
    r = parse("noon yesterday through midnight today")
    assert_equal ["2026-10-16 12:00:00 -04:00", "2026-10-18 00:00:00 -04:00"], [wall(r.begin), wall(r.end)]
    assert_equal ["2026-10-16 12:00:00 -04:00"], alt_walls(r)
    assert_equal "2026-10-17 00:00:00 -04:00", wall(r.alternatives[0].end)
  end

  def test_what_follows_oclock_is_kept
    assert_equal "2026-10-18 23:00:00 -04:00", wall(parse("11 o'clock pm tomorrow").begin)
    assert_equal "2026-10-17 23:00:00 -04:00", wall(parse("11 o'clock tonight").begin)
    r = parse("11 o'clock lunchtime")
    assert_equal ["2026-10-18 11:00:00 -04:00", []], [wall(r.begin), alt_walls(r)]
  end

  def test_d14_an_approximate_time_anywhere_in_the_phrase_is_the_exact_time_flagged
    {
      "tomorrow around 10am" => "2026-10-18 10:00:00 -04:00",
      "friday at about 2pm" => "2026-10-23 14:00:00 -04:00",
      "3pm approximately" => "2026-10-17 15:00:00 -04:00",
      "approx 6pm" => "2026-10-17 18:00:00 -04:00",
      "circa 5 in the morning" => "2026-10-18 05:00:00 -04:00",
      "3pm-ish" => "2026-10-17 15:00:00 -04:00",
      "noonish" => "2026-10-18 12:00:00 -04:00",
      "11ish" => "2026-10-18 11:00:00 -04:00",
      "in about 5 hours" => "2026-10-17 19:00:00 -04:00"
    }.each do |text, at|
      r = parse(text)
      assert_equal at, wall(r.begin), text
      assert_includes r.assumptions.map(&:code), :approximate, text
    end
    assert_equal ["2026-10-17 14:00:00 -04:00", "2026-10-17 17:00:00 -04:00"], span("within around 3 hours")
    refute_includes parse("tomorrow 10am").assumptions.map(&:code), :approximate
  end

  def test_d14_ish_after_a_short_word_is_no_suffix
    assert_raises(Acute::ParseError) { parse("dish") }
    assert_raises(Acute::ParseError) { parse("wish") }
  end

  def test_d2_eod_and_end_of_day_before_a_day_are_that_days_last_second
    assert_equal "2026-10-17 23:59:59 -04:00", wall(parse("EOD").begin)
    assert_equal "2026-10-18 23:59:59 -04:00", wall(parse("eod tomorrow").begin)
    assert_equal "2026-10-23 23:59:59 -04:00", wall(parse("end of day friday").begin)
    assert_equal ["2026-10-17 14:00:00 -04:00", "2026-10-18 00:00:00 -04:00"], span("by EOD")
    assert_equal ["2026-10-17 14:00:00 -04:00", "2026-10-17 23:59:00 -04:00"], span("until 23:59")
  end

  def test_d35_early_or_late_before_a_day_and_its_part_is_that_part_of_the_day
    assert_equal ["2026-10-18 17:00:00 -04:00", "2026-10-18 19:00:00 -04:00"], span("early tomorrow evening")
    assert_equal ["2026-10-18 09:00:00 -04:00", "2026-10-18 12:00:00 -04:00"], span("late tomorrow morning")
    r = parse("early saturday evening")
    assert_equal ["2026-10-17 17:00:00 -04:00", ["2026-10-24 17:00:00 -04:00"]], [wall(r.begin), alt_walls(r)]
  end

  def test_a_season_of_a_year
    assert_equal "2028-03-01 00:00:00 -05:00", wall(parse("spring of 2028").begin)
    assert_equal "2027-06-01 00:00:00 -04:00", wall(parse("summer of next year").begin)
  end

  def test_d31_within_the_next_n_units_is_within_n_units
    assert_equal ["2026-10-17 14:00:00 -04:00", "2026-10-17 20:00:00 -04:00"], span("within the next 6 hours")
  end

  def test_d2_eom_eoy_bom_boy_are_this_months_or_years_edge
    assert_equal "2026-10-31 00:00:00 -04:00", wall(parse("EOM").begin)
    assert_equal "2026-12-31 00:00:00 -05:00", wall(parse("at the EOY").begin)
    assert_equal "2026-10-01 00:00:00 -04:00", wall(parse("the BOM").begin)
    assert_equal ["2026-10-17 14:00:00 -04:00", "2026-11-01 00:00:00 -04:00"], span("by EOM")
  end

  def test_d9_up_to_a_day_leaves_it_out
    assert_equal ["2026-10-17 14:00:00 -04:00", "2026-10-19 00:00:00 -04:00"], span("up to monday")
    assert_equal ["2026-10-17 14:00:00 -04:00", "2026-10-17 17:00:00 -04:00"], span("up to 5pm")
  end

  def test_now_said_other_ways
    %w[right\ now just\ now at\ the\ moment at\ present at\ this\ time].each do |text|
      assert_equal "2026-10-17 14:00:00 -04:00", wall(parse(text).begin), text
    end
    assert_equal "2026-10-17 12:00:00 -04:00", wall(parse("now - 2 hours").begin)
  end

  def test_a_couple_is_two_and_only_before_a_unit
    assert_equal "2026-10-15 14:00:00 -04:00", wall(parse("a couple of days ago").begin)
    assert_equal "2026-10-31 14:00:00 -04:00", wall(parse("in a couple weeks").begin)
    assert_raises(Acute::ParseError) { parse("at a couple of") }
  end

  def test_a_time_or_day_a_week_on
    assert_equal "2026-10-18 14:00:00 -04:00", wall(parse("this time tomorrow").begin)
    assert_equal "2026-10-24 14:00:00 -04:00", wall(parse("same time next week").begin)
    assert_equal "2026-10-24 00:00:00 -04:00", wall(parse("a week today").begin)
    assert_equal "2026-10-25 00:00:00 -04:00", wall(parse("tomorrow week").begin)
    assert_equal "2026-10-27 00:00:00 -04:00", wall(parse("a week on tuesday").begin)
    assert_equal "2026-11-07 14:00:00 -05:00", wall(parse("in three weeks' time").begin)
    assert_raises(Acute::ParseError) { parse("this time") }
  end

  def test_unicode_spaces_and_dashes_are_spaces_and_dashes
    assert_equal "2026-10-17 20:00:00 -04:00", wall(parse("8\u202fpm").begin)
    assert_equal "2026-10-17 20:43:00 -04:00", wall(parse("8:43\u00a0pm").begin)
    assert_equal ["2026-10-20 00:00:00 -04:00", "2026-10-23 00:00:00 -04:00"], span("tue \u2013 thu")
  end

  def test_d44_a_days_range_in_one_month_takes_the_year_at_its_end
    assert_equal ["2021-06-12 00:00:00 -04:00", "2021-06-15 00:00:00 -04:00"], span("June 12-14, 2021")
    assert_equal ["2012-08-10 00:00:00 -04:00", "2012-08-23 00:00:00 -04:00"], span("August 10 to 22 2012")
    assert_equal ["2012-08-10 00:00:00 -04:00", "2012-08-23 00:00:00 -04:00"], span("10 - 22 August 2012")
    assert_equal ["2021-06-12 00:00:00 -04:00", "2021-06-15 00:00:00 -04:00"], span("12-14 June 2021")
    assert_equal ["2010-05-08 00:00:00 -04:00", "2010-05-12 00:00:00 -04:00"], span("eighth to eleventh May 2010")
    assert_raises(Acute::ParseError) { parse("first to second") }
  end

  def test_two_letter_weekdays
    assert_equal "1969-05-06 00:00:00 -04:00", wall(parse("Tu, May 6, 1969").begin)
    assert_equal "2005-12-30 00:00:00 -05:00", wall(parse("Fr December 30th 2005").begin)
  end

  def test_the_year_and_written_years
    assert_equal ["2000-01-01 00:00:00 -05:00", :year], [wall(parse("the year 2000").begin), parse("the year 2000").grain]
    assert_equal "1989-10-01 00:00:00 -04:00", wall(parse("1st oct in the year '89").begin)
    assert_equal "1995-01-01 00:00:00 -05:00", wall(parse("nineteen ninety five").begin)
    assert_equal "2010-01-01 00:00:00 -05:00", wall(parse("the year twenty ten").begin)
    assert_equal "1995-06-01 00:00:00 -04:00", wall(parse("summer of nineteen ninety five").begin)
    assert_equal "1776-01-01 00:00:00 -04:56", wall(parse("seventeen seventy six").begin)
    assert_equal "2026-10-18 10:30:00 -04:00", wall(parse("ten thirty").begin)
    assert_raises(Acute::ParseError) { parse("fourteen thirty") }
    assert_equal "2000-01-01 00:00:00 -05:00", wall(parse("the year two thousand").begin)
    assert_equal "2018-01-01 00:00:00 -05:00", wall(parse("two thousand and eighteen").begin)
    assert_equal "2010-01-01 00:00:00 -05:00", wall(parse("two thousand ten").begin)
  end

  def test_d44_a_clock_said_with_oh
    assert_equal "2026-10-18 12:03:00 -04:00", wall(parse("twelve oh three").begin)
    assert_equal "2026-10-17 21:05:00 -04:00", wall(parse("nine zero five pm").begin)
    assert_equal "2026-10-18 12:03:00 -04:00", wall(parse("twelve-o-three").begin)
    assert_raises(Acute::ParseError) { parse("oh") }
  end

  def test_spellings_of_quarter_weekend_oclock_and_lunch
    assert_equal ["2027-01-01 00:00:00 -05:00", "2027-04-01 00:00:00 -04:00"], span("next qtr")
    assert_equal ["2026-10-24 00:00:00 -04:00", "2026-10-26 00:00:00 -04:00"], span("next wkend")
    assert_equal ["2026-10-17 00:00:00 -04:00", "2026-10-19 00:00:00 -04:00"], span("this week end")
    assert_equal "2026-10-17 17:00:00 -04:00", wall(parse("5 oclock pm").begin)
    assert_equal "2026-10-18 17:00:00 -04:00", wall(parse("tomorrow at 5 o clock").begin)
    assert_equal "2026-10-18 12:00:00 -04:00", wall(parse("lunch time tomorrow").begin)
  end

  def test_d44_two_four_digit_numbers_dashed_are_years
    years = ["2014-01-01 00:00:00 -05:00", "2019-01-01 00:00:00 -05:00"]
    assert_equal years, span("2014-2018")
    assert_equal years, span("between 2014~2018")
    assert_equal years, span("from 2014 \u2013 2018")
    assert_raises(Acute::ParseError) { parse("0900-1700") }
    assert_raises(Acute::ParseError) { parse("2010-2015-86") }
    assert_raises(Acute::ParseError) { parse("~3pm") }
    assert_equal [], Acute.extract("Tel: +86 2010-2015-86", now: "2026-10-17T14:00", zone: NY).mentions
  end

  def test_d17_this_next_and_last_fiscal_year_count_from_the_one_holding_today
    assert_equal ["2026-10-01 00:00:00 -04:00", "2027-10-01 00:00:00 -04:00"], span("this fiscal year", fiscal_year_start: 10)
    assert_equal ["2027-07-01 00:00:00 -04:00", "2028-07-01 00:00:00 -04:00"], span("next financial year", fiscal_year_start: 7)
    assert_equal ["2024-11-01 00:00:00 -04:00", "2025-11-01 00:00:00 -04:00"], span("last fiscal year", fiscal_year_start: 11)
    assert_raises(Acute::ParseError) { parse("this fiscal year") }
  end

  def test_d44_halves_of_a_year_and_its_first_months
    assert_equal ["2027-01-01 00:00:00 -05:00", "2027-07-01 00:00:00 -04:00"], span("the first half of next year")
    assert_equal ["2026-07-01 00:00:00 -04:00", "2027-01-01 00:00:00 -05:00"], span("second half of 2026")
    assert_equal ["2027-01-01 00:00:00 -05:00", "2027-07-01 00:00:00 -04:00"], span("H1 2027")
    assert_equal ["2026-07-01 00:00:00 -04:00", "2027-01-01 00:00:00 -05:00"], span("h2 2026")
    assert_equal ["1997-01-01 00:00:00 -05:00", "1997-10-01 00:00:00 -04:00"], span("the first 9 months of 1997")
    assert_raises(Acute::ParseError) { parse("first half") }
    assert_raises(Acute::ParseError) { parse("H3 2026") }
  end

  def test_d44_numbers_with_spaces_between_are_a_date_with_its_year_first_or_last
    assert_equal "2014-12-28 00:00:00 -05:00", wall(parse("2014 12 28").begin)
    assert_equal "1974-10-31 00:00:00 -05:00", wall(parse("10 31 1974").begin)
    assert_equal "2027-10-12 00:00:00 -04:00", wall(parse("10 12 2027").begin)
    assert_equal "2027-12-10 00:00:00 +00:00", wall(parse("10 12 2027", zone: "Europe/London").begin)
    assert_raises(Acute::ParseError) { parse("five six 2027") }
  end

  def test_d44_dots_with_spaces_after_a_day_or_month_still_join_a_date
    assert_equal "2014-12-11 00:00:00 -05:00", wall(parse("11. 12. 2014").begin)
    assert_equal "2022-09-30 00:00:00 -04:00", wall(parse("30 . 09 . 22").begin)
    assert_equal "1978-12-22 00:00:00 -05:00", wall(parse("Dec 22. 1978").begin)
  end

  def test_d44_a_dotted_clock_beside_a_written_date
    assert_equal "2020-02-29 13:12:00 -05:00", wall(parse("29.02.2020 13.12").begin)
    r = parse("2017-06-30 8.20")
    assert_equal ["2017-06-30 08:20:00 -04:00", []], [wall(r.begin), r.alternatives]
    assert_equal "2017-06-30 08:20:00 -04:00", wall(parse("8.20 2017-06-30").begin)
  end
end
