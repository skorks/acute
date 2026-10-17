require_relative "../test_helper"

class ParserTest < Minitest::Test
  SYD = Acute.with(zone: "Australia/Sydney")

  def quietly
    was = Warning[:experimental]
    Warning[:experimental] = false
    yield
  ensure
    Warning[:experimental] = was
  end

  def test_api_examples
    assert_equal Date.new(2027, 2, 1), SYD.parse("1/2/2027").date
    assert_equal Date.new(2027, 1, 2), Acute.with(zone: NY).parse("1/2/2027").date
    assert_equal 5400, SYD.duration("90 min").seconds
  end

  def test_every_entry_point_uses_the_options
    p = Acute.with(now: "2026-10-17T14:00", zone: NY, week_start: :monday)
    assert_equal "2026-10-18 09:00:00 -04:00", wall(p.parse("tomorrow at 9am").time)
    assert_equal "2026-10-18 09:00:00 -04:00", wall(p.parse!("tomorrow at 9am").time)
    assert_equal "2026-10-19", p.parse("next week").date.iso8601
    assert_equal "2026-10-18", p.read("tomorrow").date.iso8601
    assert_equal "tomorrow at 9am", p.describe(Time.new(2026, 10, 18, 9, 0, 0, "-04:00"))
    assert_equal :match, p.verify("tomorrow", "2026-10-18").status
    assert_equal "2026-10-18", p.extract("see you tomorrow").mentions[0].value.date.iso8601
  end

  def test_a_call_overrides_the_parser
    p = Acute.with(now: "2026-10-17T14:00", zone: NY)
    assert_equal "2026-10-16", p.parse("friday", context: :past).date.iso8601
    assert_equal "Sun, Oct 18, 9am", p.describe(Time.new(2026, 10, 18, 9, 0, 0, "-04:00"), style: :calendar)
    assert_equal "Asia/Tokyo", p.with(zone: "Asia/Tokyo").parse("today").zone
    assert_raises(ArgumentError) { p.parse("today", colour: :red) }
  end

  def test_now_is_not_fixed_unless_given
    t = SYD.parse("now").time
    assert_in_delta Time.now.to_f, t.to_f, 5
    refute SYD.options.key?(:now)
  end

  def test_options_are_checked_once_when_made
    assert_raises(ArgumentError) { Acute.with(context: :sideways) }
    assert_raises(ArgumentError) { Acute.with(zone: "Mars/Olympus") }
    assert_raises(ArgumentError) { Acute.with(week_start: :wednesday) }
    assert_raises(ArgumentError) { Acute.with(now: "yesterday-ish") }
    assert_raises(ArgumentError) { Acute.with(colour: :red) }
  end

  def test_d45_a_zone_carried_by_now_becomes_the_parsers
    now = Time.new(2026, 10, 17, 14, 0, 0, TZInfo::Timezone.get("Asia/Tokyo"))
    p = Acute.with(now: now)
    assert_equal "Asia/Tokyo", p.options[:zone]
    assert_equal "2026-10-18", p.parse("tomorrow").date.iso8601
  end

  def test_frozen_and_shareable
    locale = +"en-GB"
    p = Acute.with(now: Time.new(2026, 10, 17, 14, 0, 0, "+01:00"), zone: "Europe/London", locale: locale)
    assert p.frozen?
    assert Ractor.shareable?(p)
    refute locale.frozen?
    assert_equal '#<Acute::Parser now: 2026-10-17 13:00:00 UTC, zone: "Europe/London", context: :future, locale: "en-GB">', p.inspect
  end

  def test_threads_share_a_parser
    p = Acute.with(now: "2026-10-17T14:00", zone: "Europe/London")
    texts = ["tomorrow at 4pm", "3/4", "next friday 3pm", "in 3 hours"] * 5
    expected = texts.map { p.parse(_1).iso8601 }
    assert_equal expected, texts.map { |t| Thread.new { p.parse(t).iso8601 } }.map(&:value)
  end

  def test_ractors_share_a_parser
    p = Acute.with(now: "2026-10-17T14:00", zone: "Australia/Sydney")
    out = quietly do
      Ractor.new(p) { |q| [q.parse("1/2/2027").date.iso8601, q.describe(q.parse("tomorrow at 9am"), style: :calendar)] }.value
    end
    assert_equal ["2027-02-01", "Sun 18 Oct, 9am"], out
  end
end
