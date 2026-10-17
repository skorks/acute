require_relative "../test_helper"

# D15, D28: the built-in holidays are formulas chosen by the locale
class HolidaysTest < Minitest::Test
  def assert_day(text, day, **opts)
    assert_equal "#{day} 00:00", parse(text, **opts).begin.strftime("%F %R"), text
  end

  def test_western_easter
    { 2000 => "2000-04-23", 2008 => "2008-03-23", 2011 => "2011-04-24", 2019 => "2019-04-21",
      2038 => "2038-04-25", 2100 => "2100-03-28" }.each do |y, day|
      assert_equal day, Time.at(Acute::Calendar.easter(y) * 86_400).utc.strftime("%F"), y
    end
  end

  def test_each_kind_of_formula
    assert_day "valentine's day", "2027-02-14"
    assert_day "memorial day 2026", "2026-05-25"
    assert_day "martin luther king jr. day 2027", "2027-01-18"
    assert_day "easter", "2027-03-28"
    assert_day "good friday 2024", "2024-03-29"
    assert_day "ash wednesday 2030", "2030-03-06"
    assert_day "cyber monday 2030", "2030-12-02"
  end

  def test_written_forms
    assert_day "st. patrick's day", "2027-03-17"
    assert_day "april fools' day", "2027-04-01"
    assert_day "mlk jr. day", "2027-01-18"
    assert_day "presidents' day", "2027-02-15"
  end

  def test_the_locale_picks_the_formula_and_the_regional_holidays
    assert_day "thanksgiving", "2027-10-11", locale: "en-CA"
    assert_day "mother's day", "2027-03-07", locale: "en-GB"
    assert_day "anzac day", "2027-04-25", locale: "en-AU"
    assert_nil Acute.parse("anzac day", now: "2026-10-17T14:00", zone: NY)
  end

  def test_of_a_period_after_a_holiday_weekday_or_part_of_day
    assert_day "labor day of last year", "2025-09-01"
    assert_day "father's day of 2015", "2015-06-21"
    assert_day "tuesday of next week", "2026-10-20"
    assert_equal "2026-12-25 06:00", parse("morning of xmas").begin.strftime("%F %R")
  end

  def test_following_is_next
    assert_day "following easter", "2027-03-28"
  end
end
