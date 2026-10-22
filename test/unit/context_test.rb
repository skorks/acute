require_relative "../test_helper"

class ContextTest < Minitest::Test
  cover "Acute::Zone*" # a Ractor building a zone
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

  def test_d45_an_offset_carried_by_now_is_the_zone
    r = Acute.parse!("tomorrow at 9am", now: Time.new(2026, 10, 17, 14, 0, 0, "-04:00"))
    assert_equal ["-04:00", "2026-10-18 09:00:00 -04:00", [:zone_inferred]], [r.zone, wall(r.begin), codes(r)]
    r = Acute.parse!("today", now: Time.at(Time.utc(2026, 10, 17, 18).to_i, in: "+10:00"))
    assert_equal ["+10:00", "2026-10-18 00:00:00 +10:00"], [r.zone, wall(r.begin)]
  end

  def test_d45_a_given_zone_wins_over_an_offset_carried_by_now
    r = Acute.parse!("today", now: Time.new(2026, 10, 17, 22, 0, 0, "-04:00"), zone: "Asia/Tokyo")
    assert_equal ["Asia/Tokyo", "2026-10-18 00:00:00 +09:00", []], [r.zone, wall(r.begin), codes(r)]
  end

  def test_d45_a_local_or_utc_now_carries_no_zone
    [Time.local(2026, 10, 17, 14), Time.utc(2026, 10, 17, 18), Time.new(2026, 10, 17, 18, 0, 0, "Z"),
     Time.new(2026, 10, 17, 18, 0, 0, "-04:00").utc].each do |now|
      assert_equal Acute::Context::SYSTEM_ZONE, Acute.parse!("today", now: now).zone, now.inspect
    end
  end

  def test_system_zone_when_nothing_else_gives_one
    r = Acute.parse!("tomorrow at 9am", now: "2026-10-17T14:00")
    assert_equal Acute::Context::SYSTEM_ZONE, r.zone
    assert_equal :zone_inferred, codes(r).last
    assert_nil r.assumptions.last.rule
  end

  def test_parses_in_parallel_threads_without_interference
    zones = %w[America/New_York Asia/Kolkata Australia/Lord_Howe Europe/London UTC +05:45 Pacific/Auckland America/Sao_Paulo]
    nows = zones.each_index.map { |i| "2026-#{format("%02d", i + 3)}-1#{i}T0#{i}:30" }
    phrases = ["tomorrow at 4pm", "next friday", "in 3 hours", "march 3", "tonight", "last week", "christmas", "3/4"]
    jobs = zones.zip(nows).flat_map { |z, now| phrases.map { |text| [text, now, z] } }
    run = ->((text, now, zone)) { Acute.parse!(text, now: now, zone: zone).iso8601 }
    expected = jobs.map(&run)
    threads = jobs.each_slice(phrases.size).map do |slice|
      Thread.new { Array.new(100) { slice.map(&run) }.uniq }
    end
    assert_equal expected.each_slice(phrases.size).zip, threads.map(&:value)
  end

  # Ruby warns once that Ractors are experimental
  def quietly
    was = Warning[:experimental]
    Warning[:experimental] = false
    yield
  ensure
    Warning[:experimental] = was
  end

  def test_parses_inside_a_ractor
    texts = ["tomorrow at 4pm", "3/4", "next friday 3pm EST", "in 3 hours"]
    expected = texts.map { Acute.parse!(_1, now: "2026-10-17T14:00", zone: "Europe/London").iso8601 }
    expected << Acute.parse!("today", now: "2026-10-17T14:00", zone: "+05:45").iso8601
    out = quietly do
      ractor_value(Ractor.new(texts) do |list|
        list.map { Acute.parse!(_1, now: "2026-10-17T14:00", zone: "Europe/London").iso8601 } <<
          Acute.parse!("today", now: "2026-10-17T14:00", zone: "+05:45").iso8601
      end)
    end
    assert_equal expected, out
  end

  # The tables ship with acute, so a Ractor builds any zone itself, whether or not the main one has
  def test_a_ractor_builds_any_named_zone
    july = Time.utc(2026, 7).to_i
    out = quietly do
      ractor_value(Ractor.new(july) do |at|
        [Acute.parse!("tomorrow 3pm", now: "2026-10-17T14:00", zone: "Africa/Windhoek").iso8601,
         Acute::Zone.send(:build, "US/Pacific", "US/Pacific").offset_at(at)]
      end)
    end
    assert_equal [Acute.parse!("tomorrow 3pm", now: "2026-10-17T14:00", zone: "Africa/Windhoek").iso8601, -25_200], out
  end

  def test_rails_time_zone_when_no_zone_is_given
    zone = Struct.new(:tzinfo).new(TZInfo::Timezone.get("Asia/Tokyo"))
    Object.const_set(:ActiveSupport, Module.new)
    ActiveSupport.const_set(:TimeZone, Class.new)
    Time.singleton_class.define_method(:zone) { zone }
    r = Acute.parse!("today", now: "2026-10-17T14:00")
    assert_equal ["Asia/Tokyo", [:zone_inferred]], [r.zone, codes(r)]
    assert_equal "Asia/Kolkata", Acute.parse!("today", zone: "Asia/Kolkata").zone
  ensure
    Time.singleton_class.remove_method(:zone) if Time.singleton_class.method_defined?(:zone, false)
    Object.send(:remove_const, :ActiveSupport) if defined?(ActiveSupport)
  end

  def test_locale_follows_the_given_zone_not_one_in_the_text
    assert_equal "2027-04-03 00:00:00 +01:00", wall(parse("3/4/2027", zone: "Europe/London").begin)
    assert_equal "2027-03-04 00:00:00 -05:00", wall(parse("3/4/2027").begin)
    assert_equal "2027-04-03 00:00:00 -04:00", wall(parse("3/4/2027", locale: "en-GB").begin)
    assert_equal Acute::Locale::US, Acute::Locale.for_zone("UTC")
    assert Ractor.shareable?(Acute::Locale.for("en-AU"))
    assert_equal "NO", Acute::Locale.for_zone("Europe/Oslo").country # a tzdata link to Europe/Berlin
  end
end
