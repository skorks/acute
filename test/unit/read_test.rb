require_relative "../test_helper"

class ReadTest < Minitest::Test
  def read(text, **opts) = Acute.read(text, now: "2026-10-17T14:00", zone: NY, **opts)

  def test_a_time_is_a_result
    r = read("tomorrow at 9am")
    assert_kind_of Acute::Result, r
    assert_equal "2026-10-18 09:00:00 -04:00", wall(r.time)
    assert_empty codes(r)
  end

  def test_d45_a_rule_comes_first
    r = read("every friday at 5pm")
    assert_kind_of Acute::Rule, r
    assert_equal "FREQ=WEEKLY;BYDAY=FR;BYHOUR=17;BYMINUTE=0", r.rrule
    assert_kind_of Acute::Rule, read("fridays")
    assert_kind_of Acute::Result, read("next friday")
    assert_kind_of Acute::Result, read("this weekend")
    assert_nil read("every morning")
  end

  def test_a_length_is_a_duration
    d = read("1h 30m")
    assert_kind_of Acute::Duration, d
    assert_equal "PT1H30M", d.iso8601
    assert_equal "P10D", read("10 days").iso8601
  end

  def test_d45_a_time_wins_and_says_it_is_also_a_length
    r = read("1530 hrs")
    assert_kind_of Acute::Result, r
    assert_equal "2026-10-17 15:30:00 -04:00", wall(r.time)
    assert_equal [:also_duration], codes(r)
    assert_equal "D45", r.assumptions[0].rule
    assert_equal "PT1530H", Acute.duration("1530 hrs").iso8601
  end

  def test_a_decade_is_read_before_seconds
    r = read("70s")
    assert_equal "2070-01-01", r.begin.strftime("%F")
    assert_equal [:also_duration], codes(r)
  end

  def test_neither_is_nil
    assert_nil read("banana")
    assert_nil read("")
  end

  def test_context_options_reach_the_time
    assert_equal "2026-10-16", read("friday", context: :past).begin.strftime("%F")
  end

  def test_bad_input_raises_like_parse
    assert_raises(ArgumentError) { Acute.read(nil) }
    assert_raises(ArgumentError) { read("today", context: :sideways) }
  end
end
