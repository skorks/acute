require_relative "../test_helper"
require_relative "../../lib/acute/chronic"

# D47: a fraction of a second written in the text is kept, exactly
class FractionTest < Minitest::Test
  cover "Acute::Resolve*"
  def test_d47_the_fraction_is_kept_exactly
    r = parse("2013-08-01T19:30:00.345-07:00")
    assert_equal Rational(345, 1000), r.time.subsec
    assert_equal r.time, r.begin
    assert_equal "2013-08-01 22:30:00 -04:00", wall(r.time)
    assert_equal :second, r.grain
    assert_predicate r, :instant?
    assert_equal Rational(1, 10), parse("2012-01-03 01:00:00.100").time.subsec
    assert_equal Rational(123_456_789, 10**9), parse("20080227T21:26:01.123456789").time.subsec
    assert_equal Rational(181, 500), parse("21:11:35.362 UTC").time.subsec
  end

  def test_d47_the_end_is_a_second_after
    r = parse("2012-01-03 01:00:00.25")
    assert_equal 1, r.end - r.begin
    assert_equal Rational(1, 4), r.end.subsec
  end

  def test_d47_a_colon_before_three_digits_or_more_is_a_fraction
    assert_equal Rational(536, 10**6), parse("2006-08-20 15:30:30:000536").time.subsec
    assert_raises(Acute::ParseError) { parse("15:30:30:00") }
  end

  def test_d47_iso_and_json_show_the_fraction_only_when_there_is_one
    assert_equal "2013-08-01T22:30:00.345-04:00", parse("2013-08-01T19:30:00.345-07:00").iso8601
    assert_equal "2012-01-03T01:00:00.1-05:00", parse("2012-01-03 01:00:00.100").to_h[:time]
    assert_equal "2012-01-03T01:00:01.1-05:00", parse("2012-01-03 01:00:00.100").to_h[:end]
    r = parse("2012-01-03 01:00:00.000")
    assert_equal 0, r.time.subsec
    assert_equal "2012-01-03T01:00:00-05:00", r.iso8601
    assert_equal "2012-01-03T01:00:00-05:00", parse("2012-01-03 01:00:00").to_h[:time]
  end

  def test_d47_to_s_shows_the_fraction
    assert_equal "Tue, Jan 3, 2012, 1:00:00.1am EST", parse("2012-01-03 01:00:00.1").to_s
    assert_equal "Tue, Jan 3, 2012, 1am EST", parse("2012-01-03 01:00:00").to_s
  end

  def test_d47_shifts_of_the_instant_keep_it
    assert_equal "2026-10-18 13:00:00 -04:00", wall(t = parse("3 hours after 10:00:00.5").time)
    assert_equal Rational(1, 2), t.subsec
  end

  def test_d47_a_range_stays_whole_seconds
    r = parse("10:00:00.25 to 11:00:00.5")
    assert_equal 0, r.begin.subsec
    assert_equal 0, r.end.subsec
  end

  def test_d47_twenty_four_hundred_has_no_fraction
    assert_raises(Acute::ParseError) { parse("24:00:00.5") }
  end

  def test_d47_the_chronic_layer_keeps_it
    tz = ENV["TZ"]
    ENV["TZ"] = NY
    assert_equal Rational(345, 1000), Chronic.parse("2013-08-01T19:30:00.345-07:00").subsec
    assert_equal 1_309_727_495.362r, Chronic.parse("2011-07-03 21:11:35.362 UTC").to_r
    span = Chronic.parse("2012-01-03 01:00:00.100", guess: false)
    assert_equal Rational(1, 10), span.begin.subsec
    assert_equal 1, span.end - span.begin
  ensure
    ENV["TZ"] = tz
  end
end
