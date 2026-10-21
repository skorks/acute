require_relative "../test_helper"

# One or two phrases from each theme of the corpus, and the D42 details settled while adding them
class BreadthTest < Minitest::Test
  def assert_reads(text, main, alts = [], assumptions = [], **opts)
    r = parse(text, **opts)
    assert_equal main, wall(r.begin), text
    assert_equal alts, alt_walls(r), text
    assert_equal assumptions, codes(r), text
  end

  def assert_span(text, from, to, **opts)
    r = parse(text, **opts)
    assert_equal [from, to], [wall(r.begin), r.end && wall(r.end)], text
  end

  def assert_fails(text, code, **opts)
    error = assert_raises(Acute::ParseError, text) { parse(text, **opts) }
    assert_equal code, error.code, text
  end

  def test_weekdays_with_clocks_and_dates
    assert_reads "friday 3pm", "2026-10-23 15:00:00 -04:00"
    assert_reads "march 3", "2027-03-03 00:00:00 -05:00"
    assert_reads "23/10/2026", "2026-10-23 00:00:00 -04:00"
    assert_reads "2026-10-23 11:00", "2026-10-23 11:00:00 -04:00"
  end

  def test_d42_two_digit_years_fall_within_fifty_years_of_now
    assert_reads "1/2/75", "2075-01-02 00:00:00 -05:00", ["2075-02-01 00:00:00 -05:00"], [:numeric_date_order]
    assert_reads "1/2/76", "1976-01-02 00:00:00 -05:00", ["1976-02-01 00:00:00 -05:00"], [:numeric_date_order]
  end

  def test_numeric_dates_follow_the_zone_country
    assert_reads "1/2/2027", "2027-02-01 00:00:00 +00:00", ["2027-01-02 00:00:00 +00:00"], [:numeric_date_order],
                 zone: "Europe/London"
  end

  def test_relative_offsets_and_units
    assert_span "3 days ago", "2026-10-14 14:00:00 -04:00", "2026-10-14 14:00:01 -04:00"
    assert_span "in 2 hours", "2026-10-17 16:00:00 -04:00", "2026-10-17 16:00:01 -04:00"
    assert_span "next week", "2026-10-18 00:00:00 -04:00", "2026-10-25 00:00:00 -04:00"
    assert_span "Q3", "2027-07-01 00:00:00 -04:00", "2027-10-01 00:00:00 -04:00"
  end

  def test_d42_rolling_hours_count_absolute_time
    assert_reads "in 3 hours", "2026-11-01 02:30:00 -05:00", now: "2026-11-01T00:30"
  end

  def test_d42_a_number_after_rel_needs_more
    assert_fails "in 3", :incomplete
  end

  def test_d42_this_and_last_second_are_the_unit
    assert_span "this second", "2026-10-17 14:00:00 -04:00", "2026-10-17 14:00:01 -04:00"
    assert_span "last second", "2026-10-17 13:59:59 -04:00", "2026-10-17 14:00:00 -04:00"
    assert_reads "next second", "2026-10-17 14:00:01 -04:00"
    assert_reads "second tuesday of march", "2027-03-09 00:00:00 -05:00"
  end

  def test_parts_of_day
    assert_reads "this evening", "2026-10-17 17:00:00 -04:00", [], [:part_of_day_point]
    assert_span "early hours", "2026-10-18 00:00:00 -04:00", "2026-10-18 04:00:00 -04:00"
  end

  def test_d42_tonight_at_midnight_is_the_rest_of_the_night_then_the_next
    assert_reads "tonight", "2026-10-18 00:00:00 -04:00", ["2026-10-18 17:00:00 -04:00"], [:part_of_day_point],
                 now: "2026-10-18T00:00"
  end

  def test_ordinals_weekends_seasons_holidays
    assert_reads "the 3rd", "2026-11-03 00:00:00 -05:00"
    assert_reads "the first monday of the month", "2026-11-02 00:00:00 -05:00"
    assert_reads "this weekend", "2026-10-17 00:00:00 -04:00", ["2026-10-16 18:00:00 -04:00"], [:weekend_friday_evening]
    assert_reads "next summer", "2027-06-01 00:00:00 -04:00", [], [:meteorological_season]
    assert_reads "summer", "2026-12-01 00:00:00 +11:00", [], [:meteorological_season], zone: "Australia/Sydney"
    assert_reads "christmas", "2026-12-25 00:00:00 -05:00"
    assert_reads "thanksgiving", "2026-11-26 00:00:00 -05:00"
    assert_reads "thanksgiving 2027", "2027-11-25 00:00:00 -05:00"
  end

  def test_d42_this_coming_is_the_first_after_now
    assert_reads "this coming friday", "2026-10-23 00:00:00 -04:00"
  end

  def test_ranges_and_open_ends
    assert_span "monday to friday", "2026-10-19 00:00:00 -04:00", "2026-10-24 00:00:00 -04:00"
    assert_span "after 3pm", "2026-10-17 15:00:00 -04:00", nil
    assert_span "after january", "2027-02-01 00:00:00 -05:00", nil
  end

  def test_d42_a_day_after_a_dated_month_is_a_day_range
    assert_span "june 3-7", "2027-06-03 00:00:00 -04:00", "2027-06-08 00:00:00 -04:00"
  end

  def test_d42_after_a_holiday_keeps_this_years_once_passed
    assert_span "after christmas", "2026-12-26 00:00:00 -05:00", nil, now: "2026-12-27T10:00"
  end

  def test_d42_digits_to_digits_is_a_range_but_word_minutes_are_minutes_to
    assert_span "5 to 9", "2026-10-17 17:00:00 -04:00", "2026-10-17 21:00:00 -04:00"
    assert_span "9-5", "2026-10-17 09:00:00 -04:00", "2026-10-17 17:00:00 -04:00"
    assert_reads "five to 9", "2026-10-18 08:55:00 -04:00", ["2026-10-17 20:55:00 -04:00"],
                 %i[bare_hour_window next_occurrence]
    assert_span "from five to nine", "2026-10-17 17:00:00 -04:00", "2026-10-17 21:00:00 -04:00"
  end

  def test_approx_fuzzy_business
    assert_reads "around noon", "2026-10-18 12:00:00 -04:00", [], %i[approximate next_occurrence]
    assert_reads "approximately 3pm", "2026-10-17 15:00:00 -04:00", [], [:approximate] # a word over 12 letters
    assert_span "early next week", "2026-10-19 00:00:00 -04:00", "2026-10-21 00:00:00 -04:00"
    assert_reads "next business day", "2026-10-19 00:00:00 -04:00"
  end

  def test_zones_in_text
    assert_reads "3pm EST", "2026-10-17 16:00:00 -04:00", [], [:fixed_offset]
  end

  def test_d42_a_dash_offset_after_a_clock
    assert_reads "15:45 -0800", "2026-10-17 19:45:00 -04:00", [], [:fixed_offset]
  end

  # D40, D44
  def test_a_weekday_said_on_that_day_after_it_is_over_notes_that_it_comes_second
    assert_reads "saturday at noon", "2026-10-24 12:00:00 -04:00", ["2026-10-17 12:00:00 -04:00"], [:same_day_passed]
    assert_reads "saturday at noon", "2026-10-17 12:00:00 -04:00", ["2026-10-24 12:00:00 -04:00"], [:same_day_or_next],
                 now: "2026-10-17T10:00"
    assert_reads "saturday at 6pm", "2026-10-10 18:00:00 -04:00", ["2026-10-17 18:00:00 -04:00"], [:same_day_passed],
                 context: :past
  end

  # Found by the fuzzer: nothing inside the weekday falls on today
  def test_a_weekday_with_no_reading_on_that_day_fails_as_a_value
    assert_fails "end of4 day saturday", :invalid_date
    assert_fails "end of4 day saturday", :invalid_date, context: :past
  end

  def test_two_structure_words_read_by_context
    assert_reads "sat", "2026-10-17 00:00:00 -04:00", ["2026-10-24 00:00:00 -04:00"], [:same_day_or_next]
    assert_reads "may 3", "2027-05-03 00:00:00 -04:00"
    assert_reads "8a", "2026-10-18 08:00:00 -04:00", [], [:next_occurrence]
  end

  def test_d42_a_weekday_filter_passes_over_a_cycle_whose_date_is_passed
    assert_reads "Sat, Sep 21", "2013-09-21 00:00:00 -04:00", now: "2013-02-12T04:30"
  end

  def test_iso_ordinal_dates
    assert_reads "2026-001", "2026-01-01 00:00:00 -05:00"
    assert_reads "2024-366", "2024-12-31 00:00:00 -05:00"
    assert_reads "2026-032T10:15", "2026-02-01 10:15:00 -05:00"
    assert_nil Acute.parse("2026-366", now: "2026-10-17T14:00", zone: NY)
  end

  def test_d43_a_weekday_that_fits_no_reading_gives_way_to_the_date
    assert_reads "Sat, Sep 21", "2027-09-21 00:00:00 -04:00", [], [:weekday_mismatch]
    assert_reads "Saturday 2026-10-23 at 3pm", "2026-10-23 15:00:00 -04:00", [], [:weekday_mismatch]
    assert_reads "saturday 7/6/2018", "2018-07-06 00:00:00 -04:00", ["2018-06-07 00:00:00 -04:00"], %i[numeric_date_order weekday_mismatch]
    assert_nil Acute.parse("Sat feb 30", now: "2026-10-17T14:00", zone: NY)
  end

  def test_d43_a_weekday_may_fit_the_date_just_gone
    assert_reads "Thu Aug 10 at 4pm", "2006-08-10 16:00:00 -04:00", now: "2006-08-16T14:00"
    assert_reads "Fri Aug 10", "2006-08-10 00:00:00 -04:00", [], [:weekday_mismatch], now: "2006-08-16T14:00", context: :past
  end
end
