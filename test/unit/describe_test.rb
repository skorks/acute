require_relative "../test_helper"

class DescribeTest < Minitest::Test
  NOW = Time.new(2026, 10, 17, 14, 0, 0, "-04:00")
  GB = { now: Time.new(2026, 10, 17, 14, 0, 0, "+01:00"), zone: "Europe/London" }.freeze

  def describe(value, **opts) = Acute.describe(value, now: NOW, zone: NY, **opts)

  def ny(y, m, d, h = 0, min = 0, s = 0) = Time.new(y, m, d, h, min, s, "-04:00")

  def test_an_instant
    t = ny(2026, 10, 18, 9)
    assert_equal "tomorrow at 9am", describe(t)
    assert_equal "Sun, Oct 18, 9am", describe(t, style: :calendar)
    assert_equal "Sun 18 Oct, 9am", Acute.describe(Time.new(2026, 10, 18, 9, 0, 0, "+01:00"), **GB, style: :calendar)
    assert_equal "now", describe(NOW)
    assert_equal "today at 4:30pm", describe(ny(2026, 10, 17, 16, 30))
    assert_equal "Friday at 12pm", describe(ny(2026, 10, 23, 12))
    assert_equal "last Monday at 12am", describe(ny(2026, 10, 12))
    assert_equal "tomorrow at 9:00:30am", describe(ny(2026, 10, 18, 9, 0, 30))
  end

  def test_a_far_instant_has_its_year
    assert_equal "Thu, Sep 3, 9am", describe(ny(2026, 9, 3, 9)) # the weekday says which year
    assert_equal "Tue, Sep 3, 2030, 9am", describe(ny(2030, 9, 3, 9))
    assert_equal "Fri, Sep 3, 2027, 9am", describe(ny(2027, 9, 3, 9), context: :past)
    assert_equal "Wed, Mar 3, 9am", describe(Time.new(2027, 3, 3, 9, 0, 0, "-05:00"))
    assert_equal "Fri, Oct 18, 1850, 9am", describe(Time.new(1850, 10, 18, 9, 0, 0, "-04:56:02"))
  end

  def test_d45_a_repeated_hour_names_its_zone
    assert_equal "Sun, Nov 1, 1:30am", describe(Time.new(2026, 11, 1, 1, 30, 0, "-04:00"))
    assert_equal "Sun, Nov 1, 2026, 1:30am EST", describe(Time.new(2026, 11, 1, 1, 30, 0, "-05:00"))
  end

  def test_days_and_periods
    assert_equal "tomorrow", describe(Date.new(2026, 10, 18))
    assert_equal "Sun, Nov 1", describe(Date.new(2026, 11, 1))
    assert_equal "next week", describe(Date.new(2026, 10, 18)..Date.new(2026, 10, 24))
    assert_equal "the week of Oct 18", describe(Date.new(2026, 10, 18)..Date.new(2026, 10, 24), style: :calendar)
    assert_equal "next month", describe(parse("next month"))
    assert_equal "November", describe(parse("next month"), style: :calendar)
    assert_equal "Q4", describe(parse("this quarter"), style: :calendar)
    assert_equal "2027", describe(parse("next year"), style: :calendar)
    assert_equal "the 1990s", describe(parse("the 90s"))
    assert_equal "summer 2027", describe(parse("summer"))
  end

  def test_spans_with_clock_times
    assert_equal "today, 3–5pm", describe(parse("3pm to 5pm"))
    assert_equal "Sat, Oct 17, 11am–1pm", describe(ny(2026, 10, 17, 11)...ny(2026, 10, 17, 13), style: :calendar)
    assert_equal "Fri, Oct 23, 3–3:01pm", describe(parse("next friday 3pm").range, style: :calendar)
    assert_equal "since Oct 10, 2pm", describe(parse("last 7 days"))
    assert_equal "Oct 10, 2026, 2pm – Oct 17, 2026, 2pm", describe(parse("last 7 days"), style: :calendar)
  end

  def test_open_ranges
    assert_equal "after 3pm", describe(parse("after 3pm"))
    assert_equal "after Sat, Oct 17, 3pm", describe(parse("after 3pm"), style: :calendar)
    assert_equal "before Friday", describe(parse("before friday"))
    assert_equal "before 2pm", describe(nil...NOW)
    assert_equal "after 2pm", describe(NOW..)
  end

  def test_a_part_of_the_day_keeps_its_point
    assert_equal "tonight", describe(parse("tonight"))
    assert_equal "Friday morning", describe(parse("friday morning"))
    assert_equal "Fri, Oct 23, morning", describe(parse("friday morning"), style: :calendar)
  end

  def test_a_result_is_described_in_its_own_zone
    r = Acute.parse("tomorrow at 9am", now: NOW, zone: "Asia/Tokyo")
    assert_equal "Sun, Oct 18, 9am", Acute.describe(r, now: NOW, style: :calendar)
  end

  def test_durations
    assert_equal "1h 30m", Acute.describe(Acute.duration("5400s"))
    assert_equal "1h 30m", Acute.describe(Acute::Duration.new(minutes: 90))
    assert_equal "2d 3h", Acute.describe(Acute::Duration.new(days: 2, hours: 3))
    assert_equal "48h", Acute.describe(Acute::Duration.new(hours: 48))
    assert_equal "1 business day", Acute.describe(Acute.duration("1 business day"))
  end

  def test_bad_values_raise
    assert_raises(ArgumentError) { describe(NOW, style: :fancy) }
    assert_raises(ArgumentError) { describe(42) }
    assert_raises(ArgumentError) { describe(NOW..NOW) }
    assert_raises(ArgumentError) { describe(nil..nil) }
    assert_raises(ArgumentError) { describe(1..2) }
    assert_raises(ArgumentError) { describe(NOW, zone: "Mars/Olympus") }
  end
end
