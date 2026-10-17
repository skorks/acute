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
end
