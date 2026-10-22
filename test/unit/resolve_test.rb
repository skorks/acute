require_relative "../test_helper"

class ResolveTest < Minitest::Test
  cover "Acute::Resolve*"
  def assert_reads(text, main, alts = [], assumptions = [], **opts)
    r = parse(text, **opts)
    assert_equal main, wall(r.begin), text
    assert_equal alts, alt_walls(r), text
    assert_equal assumptions, codes(r), text
  end

  def test_clock_with_meridiem_is_today_when_still_to_come
    assert_reads "4pm", "2026-10-17 16:00:00 -04:00"
    assert_reads "4:30 p.m.", "2026-10-17 16:30:00 -04:00"
    assert_reads "16:30", "2026-10-17 16:30:00 -04:00"
  end

  def test_d4_bare_hour_window
    assert_reads "at 4", "2026-10-17 16:00:00 -04:00", ["2026-10-18 04:00:00 -04:00"], [:bare_hour_window]
    assert_reads "at 9", "2026-10-18 09:00:00 -04:00", ["2026-10-17 21:00:00 -04:00"], %i[bare_hour_window next_occurrence]
    assert_reads "today 9:30", "2026-10-17 09:30:00 -04:00", ["2026-10-17 21:30:00 -04:00"], [:bare_hour_window]
  end

  def test_d41_a_lone_number_is_an_hour
    assert_reads "5", "2026-10-17 17:00:00 -04:00", ["2026-10-18 05:00:00 -04:00"], [:bare_hour_window]
  end

  def test_d20_next_weekday_gives_the_coming_one_then_the_one_after
    assert_reads "next friday", "2026-10-23 00:00:00 -04:00", ["2026-10-30 00:00:00 -04:00"], [:next_two_readings],
                 now: "2026-10-19T10:00"
    assert_reads "next friday", "2026-10-23 00:00:00 -04:00" # said at the weekend, only the coming one
  end

  def test_d4_leading_zero_is_24_hour
    assert_reads "09:30", "2026-10-18 09:30:00 -04:00", [], [:next_occurrence]
    assert_reads "at 0930", "2026-10-18 09:30:00 -04:00", [], [:next_occurrence]
  end

  def test_d23_passed_times_mean_the_next_one
    assert_reads "noon", "2026-10-18 12:00:00 -04:00", [], [:next_occurrence]
    assert_reads "midday", "2026-10-18 12:00:00 -04:00", [], [:next_occurrence]
    assert_reads "midnight", "2026-10-18 00:00:00 -04:00", [], [:next_occurrence]
  end

  def test_d23_past_context_means_the_previous_one
    assert_reads "4pm", "2026-10-16 16:00:00 -04:00", [], [:previous_occurrence], context: :past
    assert_reads "noon", "2026-10-17 12:00:00 -04:00", [], [], context: :past
  end

  def test_d36_a_time_equal_to_now_is_now
    assert_reads "2pm", "2026-10-17 14:00:00 -04:00", [], [:equal_to_now]
  end

  def test_d6_midnight_with_a_day_is_its_end
    assert_reads "tomorrow midnight", "2026-10-19 00:00:00 -04:00", ["2026-10-18 00:00:00 -04:00"], [:midnight_end_of_day]
  end

  def test_d29_seconds_mean_24_hour
    r = parse("4:30:15")
    assert_equal "2026-10-18 04:30:15 -04:00", wall(r.begin)
    assert_equal :second, r.grain
    assert_equal 1, r.end - r.begin
    assert_equal %i[machine_time next_occurrence], codes(r)
  end

  def test_d30_twelve_oclock_is_pm
    assert_reads "12:30", "2026-10-18 12:30:00 -04:00", [], %i[twelve_oclock next_occurrence]
    assert_reads "12am", "2026-10-18 00:00:00 -04:00", [], [:next_occurrence]
  end

  def test_d40_tomorrow_before_4am_means_the_coming_day_first
    assert_reads "tomorrow", "2026-10-17 00:00:00 -04:00", ["2026-10-18 00:00:00 -04:00"], [:tomorrow_after_midnight],
                 now: "2026-10-17T02:00"
    assert_reads "tomorrow", "2026-10-18 00:00:00 -04:00", [], [], now: "2026-10-17T04:00"
    assert_reads "tomorrow", "2026-10-18 00:00:00 -04:00", [], [], now: "2026-10-17T00:00" # D41
    assert_reads "tomorrow", "2026-10-18 00:00:00 -04:00", [], [], now: Date.new(2026, 10, 17)
    assert_reads "tomorrow at 9am", "2026-10-17 09:00:00 -04:00", ["2026-10-18 09:00:00 -04:00"],
                 [:tomorrow_after_midnight], now: "2026-10-17T01:00"
  end

  def test_day_words_with_clocks
    assert_reads "tomorrow at 4pm", "2026-10-18 16:00:00 -04:00"
    assert_reads "4pm tomorrow", "2026-10-18 16:00:00 -04:00"
    assert_reads "yesterday at noon", "2026-10-16 12:00:00 -04:00"
    assert_reads "tmrw @ 4 pm", "2026-10-18 16:00:00 -04:00"
  end

  def test_grains
    assert_equal [:minute, 60], [parse("4pm").grain, parse("4pm").end - parse("4pm").begin]
    now = parse("now")
    assert_equal [:second, "2026-10-17 14:00:00 -04:00", 1], [now.grain, wall(now.begin), now.end - now.begin]
    today = parse("today")
    assert_equal [:day, "2026-10-17 00:00:00 -04:00", "2026-10-18 00:00:00 -04:00"], [today.grain, wall(today.begin), wall(today.end)]
  end

  def test_dst_repeated_wall_time_takes_the_earlier_instant
    r = parse("tomorrow at 1:30am", now: "2026-10-31T14:00")
    assert_equal "2026-11-01 01:30:00 -04:00", wall(r.begin)
    assert_equal [:dst_repeated_time], codes(r)
  end

  def test_dst_skipped_wall_time_moves_forward
    r = parse("tomorrow at 2:30am", now: "2027-03-13T12:00")
    assert_equal "2027-03-14 03:30:00 -04:00", wall(r.begin)
    assert_equal [:dst_skipped_time], codes(r)
  end

  # D43: an instant carries its UTC, so a shift across the fold lands on the second 1:30, not the first
  def test_a_shift_across_the_fall_back_keeps_the_later_side
    assert_equal "2026-11-01 01:30:00 -05:00", wall(parse("in 3 hours", now: "2026-10-31T23:30").begin)
    assert_equal "2026-11-01 01:30:00 -05:00", wall(parse("in 1 hour", now: "2026-11-01T01:30").begin)
  end

  def test_a_zone_abbreviation_picks_the_side_of_a_repeated_hour
    assert_equal "2026-11-01 01:30:00 -05:00", wall(parse("2026-11-01 01:30 EST").begin)
    assert_equal "2026-11-01 01:30:00 -04:00", wall(parse("2026-11-01 01:30 EDT").begin)
  end

  def test_a_day_spans_its_real_length_across_dst
    assert_equal(25 * 3600, parse("tomorrow", now: "2026-10-31T14:00").then { |r| r.end - r.begin })
    assert_equal(23 * 3600, parse("tomorrow", now: "2027-03-13T14:00").then { |r| r.end - r.begin })
  end
end
