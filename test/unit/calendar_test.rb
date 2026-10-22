require_relative "../test_helper"

class CalendarTest < Minitest::Test
  cover "Acute::Calendar*"
  C = Acute::Calendar

  EPOCH = Date.new(1970, 1, 1, Date::GREGORIAN).jd

  def each_day(from, to) = (from..to).each { |days| yield Date.jd(EPOCH + days, Date::GREGORIAN), days }

  def day(y, m, d) = Date.new(y, m, d, Date::GREGORIAN).jd - EPOCH

  # Every day of two 400-year cycles and their ends: the algorithms' guesses are off only near year ends
  def test_round_trips_day_numbers_against_ruby_date
    wrong = []
    each_day(day(1599, 12, 1), day(2401, 3, 1)) do |date, days|
      wrong << date if days != C.days_from_civil(date.year, date.month, date.day) ||
                       date.year * 10_000 + date.month * 100 + date.day != C.civil_from_days(days) ||
                       date.wday != C.weekday(days)
    end
    assert_empty wrong
  end

  def test_epoch_and_leap_days
    assert_equal 0, C.days_from_civil(1970, 1, 1)
    assert_equal 20_000_229, C.civil_from_days(C.days_from_civil(2000, 2, 29))
    assert_equal 29, C.days_in_month(2024, 2)
    assert_equal 28, C.days_in_month(1900, 2)
    assert_equal 29, C.days_in_month(2000, 2)
    assert_equal 31, C.days_in_month(2026, 12)
  end

  def test_leap_years_and_month_lengths_against_ruby_date
    (1896..2104).each do |y|
      assert_equal Date.gregorian_leap?(y), C.leap?(y), y.to_s
      (1..12).each { |m| assert_equal Date.new(y, m, -1).day, C.days_in_month(y, m), "#{y}-#{m}" }
    end
  end

  def test_iso_week_one_against_ruby_date
    (1990..2040).each do |y|
      assert_equal (Date.commercial(y, 1, 1) - Date.new(1970, 1, 1)).to_i, C.iso_week_one(y), y.to_s
    end
  end

  # D15: from published tables, including the earliest (March 22nd) and latest (April 25th) dates
  def test_easter
    { 1818 => 322, 1900 => 415, 1943 => 425, 1961 => 402, 2000 => 423, 2008 => 323, 2011 => 424, 2019 => 421,
      2024 => 331, 2025 => 420, 2026 => 405, 2027 => 328, 2038 => 425, 2100 => 328, 2285 => 322 }.each do |y, md|
      assert_equal y * 10_000 + md, C.civil_from_days(C.easter(y)), y.to_s
    end
  end

  # D15: every Gregorian year against Oudin's algorithm (1940), a different derivation of the same computus
  def test_easter_against_oudin
    wrong = (1583..9999).reject do |y|
      g = y % 19
      c = y / 100
      h = (c - c / 4 - (8 * c + 13) / 25 + 19 * g + 15) % 30
      i = h - (h / 28) * (1 - (29 / (h + 1)) * ((21 - g) / 11))
      l = i - (y + y / 4 + i + 2 - c + c / 4) % 7
      month = 3 + (l + 40) / 44
      Date.new(y, month, l + 28 - 31 * (month / 4), Date::GREGORIAN).jd - EPOCH == C.easter(y)
    end
    assert_empty wrong
  end

  # D17: stepping one weekday at a time, a weekend first moved to the Friday before (forward) or Monday after (back)
  def test_add_weekdays_against_stepping
    weekend = ->(d) { [0, 6].include?(C.weekday(d)) }
    start = C.days_from_civil(2026, 10, 12)
    (start...(start + 14)).each do |d|
      (-12..12).each do |n|
        next if n.zero?

        e = d
        e += n.positive? ? -1 : 1 while weekend.(e)
        n.abs.times do
          e += n <=> 0
          e += n <=> 0 while weekend.(e)
        end
        assert_equal e, C.add_weekdays(d, n), "#{C.civil_from_days(d)} #{n}"
      end
    end
  end

  def test_year_of_year_start_and_year_if_first_against_ruby_date
    wrong = []
    each_day(day(-401, 12, 25), day(2401, 1, 7)) do |date, days|
      wrong << date if date.year != C.year_of(days) || (date.yday == 1 ? date.year : nil) != C.year_if_first(days)
    end
    assert_empty wrong
    [-400, 0, 1, 1900, 1970, 2000, 2026, 2100].each do |y|
      assert_equal (Date.new(y, 1, 1, Date::GREGORIAN) - Date.new(1970, 1, 1)).to_i, C.year_start(y)
    end
  end
end
