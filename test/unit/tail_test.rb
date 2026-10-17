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
end
