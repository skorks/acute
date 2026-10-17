require_relative "../test_helper"

class CalendarTest < Minitest::Test
  C = Acute::Calendar

  def test_round_trips_day_numbers_against_ruby_date
    (Date.new(1899, 12, 1)..Date.new(2201, 3, 1)).step(17).each do |date|
      days = (date - Date.new(1970, 1, 1)).to_i
      assert_equal days, C.days_from_civil(date.year, date.month, date.day)
      assert_equal date.year * 10_000 + date.month * 100 + date.day, C.civil_from_days(days)
      assert_equal date.wday, C.weekday(days)
    end
  end

  def test_epoch_and_leap_days
    assert_equal 0, C.days_from_civil(1970, 1, 1)
    assert_equal 20_000_229, C.civil_from_days(C.days_from_civil(2000, 2, 29))
    assert_equal 29, C.days_in_month(2024, 2)
    assert_equal 28, C.days_in_month(1900, 2)
    assert_equal 29, C.days_in_month(2000, 2)
    assert_equal 31, C.days_in_month(2026, 12)
  end
end
