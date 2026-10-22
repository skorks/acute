require_relative "../test_helper"

# D13: week numbers are ISO 8601 weeks, Monday to Sunday, week 1 holding January 4th
class IsoWeeksTest < Minitest::Test
  cover "Acute::Resolve*"
  def span(text, **opts)
    r = parse(text, **opts)
    "#{r.begin.strftime("%F")}..#{r.end.strftime("%F")}"
  end

  def test_week_one_against_ruby_date
    (1990..2040).each do |y|
      assert_equal (Date.commercial(y, 1, 1) - Date.new(1970, 1, 1)).to_i, Acute::Calendar.iso_week_one(y), y
    end
  end

  def test_written_forms_with_a_year
    assert_equal "2026-10-12..2026-10-19", span("2026-W42")
    assert_equal "2025-12-29..2026-01-05", span("2026W01")
    assert_equal "2026-12-28..2027-01-04", span("week 53 of 2026")
    assert_equal "2024-12-30..2025-01-06", span("W1 2025")
  end

  def test_a_day_of_the_week
    assert_equal "2026-10-14..2026-10-15", span("2026-W42-3")
    assert_equal "2027-01-03..2027-01-04", span("2026-W53-7")
  end

  def test_week_53_only_in_a_long_year
    assert_nil Acute.parse("week 53 of 2025", now: "2026-10-17T14:00", zone: NY)
  end

  def test_a_bare_week_is_this_year_s_until_it_is_over
    assert_equal "2026-10-12..2026-10-19", span("week 42")
    assert_equal "2027-10-11..2027-10-18", span("week 41")
    assert_equal "2028-01-03..2028-01-10", span("week 1", now: "2027-12-29T09:00", zone: "Europe/Berlin")
  end

  def test_a_count_of_weeks_is_not_a_week_number
    assert_equal "2026-10-31", parse("2 weeks from today").begin.strftime("%F")
  end
end
