require_relative "../test_helper"

# D44: shifts by several counts, signed counts, fractions, and shifts beside a day
class ShiftsTest < Minitest::Test
  def assert_at(text, expected, **opts)
    assert_equal expected, wall(parse(text, **opts).begin), text
  end

  def test_several_counts_apply_in_the_order_said
    assert_at "1 week and a day from now", "2026-10-25 14:00:00 -04:00"
    assert_at "2 years 4 months 5 days ago", "2024-06-12 14:00:00 -04:00"
    assert_at "1 year, 7 months ago", "2025-03-17 14:00:00 -04:00"
    assert_at "in 2 hours and 30 minutes", "2026-10-17 16:30:00 -04:00"
    assert_at "1 month 21 days ago", "2017-10-02 00:00:00 +00:00", now: "2017-11-23T00:00", zone: "UTC"
  end

  def test_signed_counts
    assert_at "+2 days", "2026-10-19 14:00:00 -04:00"
    assert_at "-3y", "2023-10-17 14:00:00 -04:00"
    assert_at "- 3 seconds", "2026-10-17 13:59:57 -04:00"
    assert_at "-2hr5min", "2026-10-17 11:55:00 -04:00"
    assert_at "+1 decade -2 years", "2034-10-17 14:00:00 -04:00"
    assert_at "2023-12-29 -10days", "2023-12-19 00:00:00 -05:00"
    assert_equal 86_400, parse("2023-12-29 -10days").then { _1.end - _1.begin }
  end

  def test_a_minus_that_is_an_offset_or_a_range_stays_one
    assert_at "15:45 -0800", "2026-10-17 19:45:00 -04:00"
    assert_equal 2 * 3600, parse("3:00 - 5:00 pm").then { _1.end - _1.begin }
  end

  def test_fractional_counts
    assert_at "in 2.5 hours", "2026-10-17 16:30:00 -04:00"
    assert_at "in 10.75 minutes", "2026-10-17 14:10:45 -04:00"
    assert_at "half an hour ago", "2026-10-17 13:30:00 -04:00"
    assert_at "1/2 hour ago", "2026-10-17 13:30:00 -04:00"
    assert_at "half past 3", "2026-10-17 15:30:00 -04:00"
  end

  def test_in_takes_any_spoken_length
    assert_at "in an hour and a half", "2026-10-17 15:30:00 -04:00"
    assert_at "in three and a half hours", "2026-10-17 17:30:00 -04:00"
    assert_at "in a quarter of an hour", "2026-10-17 14:15:00 -04:00"
    assert_at "in 2 more minutes", "2026-10-17 14:02:00 -04:00"
    assert_at "in a pair of minutes", "2026-10-17 14:02:00 -04:00"
    assert_at "in 1 hour 30", "2026-10-17 15:30:00 -04:00"
    assert_at "an hour and a half ago", "2026-10-17 12:30:00 -04:00"
    assert_at "in a quarter", "2027-01-17 14:00:00 -05:00"
  end

  def test_d44_for_a_length_from_a_start_is_that_long_from_it
    r = parse("for 3 days from today")
    assert_equal ["2026-10-17 00:00:00 -04:00", "2026-10-20 00:00:00 -04:00"], [wall(r.begin), wall(r.end)]
    r = parse("for 1 week, from 20th dec")
    assert_equal ["2026-12-20 00:00:00 -05:00", "2026-12-27 00:00:00 -05:00"], [wall(r.begin), wall(r.end)]
    r = parse("for 2 hours starting 3pm")
    assert_equal ["2026-10-17 15:00:00 -04:00", "2026-10-17 17:00:00 -04:00"], [wall(r.begin), wall(r.end)]
    assert_raises(Acute::ParseError) { parse("for 3 days") }
  end

  def test_a_shift_beside_a_fixed_day_moves_it
    assert_at "3 years ago tomorrow", "2023-10-18 00:00:00 -04:00"
  end

  def test_a_shift_beside_a_recurring_day_is_the_one_inside_the_shifted_period
    assert_at "2 years ago 1st September", "2024-09-01 00:00:00 -04:00"
    assert_at "september 3 years ago", "2023-09-01 00:00:00 -04:00"
    assert_at "thanksgiving in 9 months", "2027-11-25 00:00:00 -05:00"
    assert_at "first monday in 2 months", "2026-12-07 00:00:00 -05:00"
    assert_at "1 week ago Saturday", "2026-10-10 00:00:00 -04:00"
  end

  def test_a_count_of_days_that_recur_is_the_nth_one_after_or_before
    assert_at "3 fridays from now", "2026-11-06 00:00:00 -05:00"
    assert_at "1 saturday from now", "2026-10-24 00:00:00 -04:00"
    assert_at "2 saturdays ago", "2026-10-03 00:00:00 -04:00"
    assert_at "2nd monday before christmas", "2026-12-14 00:00:00 -05:00"
    assert_at "2 weekends from now", "2026-10-31 00:00:00 -04:00"
    assert_at "2 black fridays ago", "2024-11-29 00:00:00 -05:00"
    assert_at "11:59 on 3 sundays after next wed", "2026-11-08 11:59:00 -05:00"
  end

  def test_a_plural_day_without_a_count_recurs_and_is_no_time
    assert_raises(Acute::ParseError) { parse("fridays") }
    assert_raises(Acute::ParseError) { parse("next fridays") }
  end

  def test_weekdays_are_business_days
    assert_at "this weekday", "2026-10-19 00:00:00 -04:00"
    assert_at "last weekday", "2026-10-16 00:00:00 -04:00"
    assert_at "next weekday", "2026-10-19 00:00:00 -04:00"
    assert_at "last weekday of the month", "2026-10-30 00:00:00 -04:00"
    assert_at "first weekday of november", "2026-11-02 00:00:00 -05:00"
    assert_at "3 weekdays ago", "2026-10-14 14:00:00 -04:00"
  end

  def test_d44_final_is_the_last_one_of
    assert_at "final thursday in april", "2027-04-29 00:00:00 -04:00"
    assert_at "the final day of june", "2027-06-30 00:00:00 -04:00"
    assert_raises(Acute::ParseError) { parse("final friday after christmas") }
    assert_raises(Acute::ParseError) { parse("final 3 days") }
  end

  # today's morning is over, so it is the first one ago; tonight has not begun, so it is the first one ahead
  def test_d46_parts_of_the_day_count_as_weekdays_do
    assert_at "5 mornings ago", "2026-10-13 06:00:00 -04:00"
    assert_at "two nights ago", "2026-10-15 21:00:00 -04:00"
    assert_at "3 evenings from now", "2026-10-19 17:00:00 -04:00"
    assert_raises(Acute::ParseError) { parse("mornings") }
    assert_raises(Acute::ParseError) { parse("this mornings") }
  end
end
