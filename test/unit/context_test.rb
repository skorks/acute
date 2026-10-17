require_relative "../test_helper"

class ContextTest < Minitest::Test
  def test_now_as_date_means_its_start
    assert_equal "2026-10-17 16:00:00 -04:00", wall(parse("4pm", now: Date.new(2026, 10, 17)).begin)
  end

  def test_now_as_iso_string_with_offsets
    assert_equal "2026-10-17 14:00:00 -04:00", wall(parse("now", now: "2026-10-17T18:00:00Z").begin)
    assert_equal "2026-10-17 14:00:00 -04:00", wall(parse("now", now: "2026-10-17T20:00:00.250+02:00").begin)
    assert_equal "2026-10-17 00:00:00 -04:00", wall(parse("now", now: "2026-10-17").begin)
  end

  def test_now_as_time_and_datetime
    t = Time.utc(2026, 10, 17, 18)
    assert_equal "2026-10-17 14:00:00 -04:00", wall(parse("now", now: t).begin)
    assert_equal "2026-10-17 14:00:00 -04:00", wall(parse("now", now: t.to_datetime).begin)
  end

  def test_given_zone_is_not_an_assumption
    refute_includes codes(parse("today", zone: "Asia/Kolkata")), :zone_inferred
    assert_equal "Asia/Kolkata", parse("today", zone: TZInfo::Timezone.get("Asia/Kolkata")).zone
    assert_equal "+05:45", parse("today", zone: "+05:45").zone
  end

  def test_zone_carried_by_now
    now = Time.at(Time.utc(2026, 10, 17, 5).to_i, in: TZInfo::Timezone.get("Asia/Tokyo"))
    r = Acute.parse!("today", now: now)
    assert_equal ["Asia/Tokyo", "2026-10-17 00:00:00 +09:00"], [r.zone, wall(r.begin)]
    assert_equal [:zone_inferred], codes(r)
  end

  def test_system_zone_when_nothing_else_gives_one
    r = Acute.parse!("tomorrow at 9am", now: "2026-10-17T14:00")
    assert_equal Acute::Context::SYSTEM_ZONE, r.zone
    assert_equal :zone_inferred, codes(r).last
    assert_nil r.assumptions.last.rule
  end

  def test_parses_in_parallel_threads_without_interference
    zones = %w[America/New_York Asia/Kolkata Australia/Lord_Howe Europe/London UTC +05:45 Pacific/Auckland America/Sao_Paulo]
    expected = zones.map { |z| Acute.parse!("tomorrow at 4pm", now: "2026-10-17T14:00", zone: z).iso8601 }
    threads = zones.map do |z|
      Thread.new { Array.new(200) { Acute.parse!("tomorrow at 4pm", now: "2026-10-17T14:00", zone: z).iso8601 }.uniq }
    end
    assert_equal expected.map { [_1] }, threads.map(&:value)
  end
end
