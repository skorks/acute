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
end
