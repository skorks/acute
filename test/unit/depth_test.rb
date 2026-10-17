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
end
