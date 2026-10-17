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

  def test_d48_more_formula_holidays
    assert_day "election day 2015", "2015-11-03"
    assert_day "administrative professionals' day 2010", "2010-04-21"
    assert_day "secretaries' day 2019", "2019-04-24"
    assert_day "national grandparents day 2019", "2019-09-08"
    assert_day "military spouse day 2018", "2018-05-11"
    assert_day "lincoln's birthday", "2027-02-12"
    assert_day "the ides of march", "2027-03-15"
    assert_day "next fourth of july", "2027-07-04"
  end

  def test_d48_other_names_for_built_in_holidays
    assert_day "st paddy's day", "2027-03-17"
    assert_day "decoration day 2027", "2027-05-31"
    assert_day "washington's birthday 2027", "2027-02-15"
    assert_day "pancake day 2027", "2027-02-09"
    assert_day "thanks giving day", "2026-11-26"
  end

  def test_d48_may_day_is_the_first_monday_in_britain
    assert_day "may day 2027", "2027-05-01"
    assert_day "may day 2027", "2027-05-03", locale: "en-GB"
  end

  def test_d48_regional_holidays_need_their_locale
    assert_day "day of the vow", "2026-12-16", locale: "en-ZA"
    assert_day "dominion day", "2027-07-01", locale: "en-CA"
    assert_day "sovereign's birthday 2018", "2018-05-21", locale: "en-CA"
    assert_nil Acute.parse("rizal day", now: "2026-10-17T14:00", zone: NY)
  end

  def test_d48_kwanzaa_is_its_first_day_then_its_week
    r = parse("kwanzaa")
    assert_equal "2026-12-26 00:00", r.begin.strftime("%F %R")
    assert_equal ["2026-12-26 00:00:00 -05:00"], alt_walls(r)
    assert_equal "2027-01-02 00:00", r.alternatives[0].end.strftime("%F %R")
  end

  def test_d48_a_holiday_weekend_takes_in_a_monday_or_friday_holiday
    r = parse("labor day weekend 2027")
    assert_equal ["2027-09-04 00:00:00 -04:00", "2027-09-07 00:00:00 -04:00"], [wall(r.begin), wall(r.end)]
    assert_equal ["2027-09-03 18:00:00 -04:00"], alt_walls(r)
    r = parse("good friday weekend", now: "2027-01-10T12:00")
    assert_equal ["2027-03-26 00:00:00 -04:00", "2027-03-29 00:00:00 -04:00"], [wall(r.begin), wall(r.end)]
  end

  def test_following_is_next
    assert_day "following easter", "2027-03-28"
  end
end
