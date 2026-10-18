require_relative "../test_helper"

# D44: dates and times written with no words: compact ISO, year first, month and year, dotted clocks
class CompactTest < Minitest::Test
  def assert_span(text, begin_wall, seconds, **opts)
    r = parse(text, **opts)
    assert_equal begin_wall, wall(r.begin), text
    assert_equal seconds, r.end - r.begin, text
    assert_empty r.alternatives, text
  end

  def test_compact_iso_dates_and_their_times
    assert_span "20261123", "2026-11-23 00:00:00 -05:00", 86_400
    assert_span "20030925T104941", "2003-09-25 10:49:41 -04:00", 1
    assert_span "20030925T1049", "2003-09-25 10:49:00 -04:00", 60
    assert_span "19980915T09:05:32", "1998-09-15 09:05:32 -04:00", 1
    assert_span "20261123T154530Z", "2026-11-23 10:45:30 -05:00", 1
    assert_span "20030925T104941-0300", "2003-09-25 09:49:41 -04:00", 1
    assert_nil Acute.parse("20261323", now: "2026-10-17T14:00", zone: NY)
  end

  def test_a_week_and_its_day_in_three_digits
    assert_span "2026W481", "2026-11-23 00:00:00 -05:00", 86_400
    assert_span "1997W011", "1996-12-30 00:00:00 -05:00", 86_400
  end

  def test_four_digits_first_is_always_year_first
    assert_span "2026/11/23", "2026-11-23 00:00:00 -05:00", 86_400
    assert_span "2026.11.23", "2026-11-23 00:00:00 -05:00", 86_400, locale: "en-GB"
  end

  def test_a_month_and_its_year
    assert_span "11/2026", "2026-11-01 00:00:00 -04:00", 30 * 86_400 + 3600
    assert_span "2013/12", "2013-12-01 00:00:00 -05:00", 31 * 86_400
  end

  def test_dotted_clocks_before_am_or_pm
    assert_span "9.30pm", "2026-10-17 21:30:00 -04:00", 60
    assert_span "12.31 A.M.", "2026-10-18 00:31:00 -04:00", 60
    assert_span "01.03.12pm", "2026-10-18 13:03:12 -04:00", 1
    assert_equal "2014-12-11", parse("11.12.2014").begin.strftime("%F")
  end

  def test_d44_twelve_or_fourteen_digits_are_a_date_and_its_time
    assert_span "19970902090807", "1997-09-02 09:08:07 -04:00", 1
    assert_span "199709020908", "1997-09-02 09:08:00 -04:00", 60
    assert_equal "2004-04-24 23:05:41 +00:00", wall(parse("20040425010541 CEST", zone: "UTC").begin)
    assert_raises(Acute::ParseError) { parse("123456789012") }
  end

  def test_d44_an_apostrophe_year_or_one_past_31_comes_first
    assert_equal "1969-05-31", parse("'69-5-31", now: "2010-06-15T14:00").begin.strftime("%F")
    assert_equal "1969-05-31", parse("'69.05.31", now: "2010-06-15T14:00").begin.strftime("%F")
    assert_equal "1978-12-22", parse("78-12-22", now: "2010-06-15T14:00").begin.strftime("%F")
  end

  def test_d44_24_00_is_the_end_of_the_day
    assert_span "24:00", "2026-10-18 00:00:00 -04:00", 60
    assert_span "24 o'clock", "2026-10-18 00:00:00 -04:00", 60
    assert_span "2026-10-23 24:00", "2026-10-24 00:00:00 -04:00", 60
    assert_raises(Acute::ParseError) { parse("24:01") }
    assert_raises(Acute::ParseError) { parse("24:00 pm") }
  end

  def test_d44_four_digits_before_am_or_pm_are_a_clock
    assert_span "1140 a.m.", "2026-10-18 11:40:00 -04:00", 60
    assert_span "oct 5 2012 1045pm", "2012-10-05 22:45:00 -04:00", 60
    assert_raises(Acute::ParseError) { parse("1300 pm") }
  end

  def test_d44_am_or_pm_after_in_the_is_the_clocks
    assert_span "3 in the AM", "2026-10-18 03:00:00 -04:00", 60
    assert_span "from 3 to 4 in the PM", "2026-10-17 15:00:00 -04:00", 3600
  end

  def test_d44_early_or_late_before_a_part_beside_a_clock_adds_nothing
    assert_span "early morning at 8:00", "2026-10-18 08:00:00 -04:00", 60
    assert_span "Sunday late evening at 10:00", "2026-10-18 22:00:00 -04:00", 60
  end

  def test_d44_at_an_hour_then_two_digits_is_its_minutes
    r = parse("at 3 15")
    assert_equal "2026-10-17 15:15:00 -04:00", wall(r.begin)
    assert_equal(["2026-10-18 03:15:00 -04:00"], r.alternatives.map { wall(_1.begin) })
    assert_span "at 12 15", "2026-10-18 12:15:00 -04:00", 60
    assert_raises(Acute::ParseError) { parse("at 3 75") }
  end

  def test_d44_two_digits_past_31_after_a_month_are_its_year
    assert_span "dec 79", "1979-12-01 00:00:00 -05:00", 31 * 86_400
    assert_equal "2032-08-01", parse("August 32").begin.strftime("%F")
    assert_raises(Acute::ParseError) { parse("may 40 pm") }
  end

  def test_d44_hour_0_with_am_is_midnight
    assert_span "monday 0am", "2026-10-19 00:00:00 -04:00", 60
    assert_span "00:00:00 am", "2026-10-18 00:00:00 -04:00", 1
    assert_raises(Acute::ParseError) { parse("0pm") }
  end

  def test_d46_exif_dates_put_colons_for_dashes
    assert_span "2012:05:25 22:06:50", "2012-05-25 22:06:50 -04:00", 1
    assert_span "2012:05:25", "2012-05-25 00:00:00 -04:00", 86_400
  end

  def test_d46_a_bare_number_before_on_and_a_day_is_its_hour
    r = parse("5 on may 28")
    assert_equal ["2027-05-28 17:00:00 -04:00", ["2027-05-28 05:00:00 -04:00"]], [wall(r.begin), alt_walls(r)]
    assert_equal "2026-10-23 17:00:00 -04:00", wall(parse("5 on friday").begin)
    assert_includes codes(parse("5 on friday")), :bare_hour_window
  end
end
