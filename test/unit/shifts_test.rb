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
end
