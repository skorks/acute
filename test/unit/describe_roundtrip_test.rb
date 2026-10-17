require_relative "../test_helper"

# D45: parse(describe(x)) gives back x, for both styles, over many nows, zones (DST days among them), grains and
# spans. Seeded, so a failure repeats; ROUNDTRIP_SEED and ROUNDTRIP_NOWS widen the search.
class DescribeRoundTripTest < Minitest::Test
  SEED = Integer(ENV.fetch("ROUNDTRIP_SEED", 45))
  NOWS = Integer(ENV.fetch("ROUNDTRIP_NOWS", 30))
  ZONES = %w[America/New_York Europe/London Australia/Lord_Howe Australia/Sydney America/Sao_Paulo America/Havana
             Asia/Kolkata Asia/Kathmandu Pacific/Chatham Pacific/Apia America/St_Johns UTC +10:00].freeze
  PHRASES = ["tomorrow", "today", "now", "next friday", "last tuesday", "tonight", "this morning", "friday night",
             "yesterday afternoon", "this week", "next week", "last week", "this month", "next month", "q1", "q3",
             "next quarter", "this year", "last year", "the 80s", "the 2030s", "summer", "winter", "march",
             "last 7 days", "next 3 hours", "past 2 weeks", "3pm to 5pm", "11pm to 1am", "after 3pm", "before noon",
             "since monday", "until friday", "after christmas", "before thanksgiving", "in 2 hours", "3 days ago",
             "next friday 3pm", "monday 9:30am", "the 3rd at 8pm", "noon tomorrow", "midnight", "this weekend",
             "next weekend", "jan 1 to jan 10", "december", "new year's eve", "easter", "the 15th",
             "2 weeks from now", "in 90 seconds", "45 minutes ago", "1:30am", "2:30am"].freeze
  STYLES = %i[relative calendar].freeze
  DAY = 86_400

  def setup
    @rng = Random.new(SEED)
    @misread = []
    @checked = 0
  end

  def test_d45_describe_reads_back
    nows.each do |now, zone|
      opts = { now: now, zone: zone, locale: %w[en-US en-GB].sample(random: @rng),
               context: @rng.rand < 0.2 ? :past : :future }
      targets(now, zone, opts).each { |x| STYLES.each { check(x, opts.merge(style: _1)) } }
    end
    durations
    assert_operator @checked, :>, 10_000
    assert_empty @misread.first(30), "#{@misread.size} of #{@checked} did not read back"
  end

  private

  # Random nows in each zone, and nows on either side of the zone's clock changes
  def nows
    ZONES.flat_map do |zone|
      changes = transitions(zone)
      Array.new(NOWS) do |i|
        at = i.even? && changes.any? ? changes.sample(random: @rng) + @rng.rand(-2 * DAY..2 * DAY) : epoch(1960, 2090)
        [Time.at(at - at % 60), zone]
      end
    end
  end

  def targets(now, zone, opts)
    n = now.to_i
    changes = transitions(zone).select { (_1 - n).abs < 400 * DAY }
    near = -> { @rng.rand < 0.5 && changes.any? ? changes.sample(random: @rng) + @rng.rand(-3 * 3600..3 * 3600) : n + @rng.rand(-400 * DAY..400 * DAY) }
    out = []
    6.times { out << Time.at(round(near.call)) }
    out << Time.at(near.call) << now << Time.at(epoch(1900, 2100) / 60 * 60)
    3.times do
      b = round(near.call)
      e = b + [60, 900, 3600, 7200, 3 * 3600, DAY, 3 * DAY + 3600].sample(random: @rng) * @rng.rand(1..3)
      out << (Time.at(b)...Time.at(e)) << (Time.at(b)..) << (..Time.at(e))
    end
    2.times do
      d = Time.at(near.call).getlocal(Acute::Zone.for(zone).offset_at(n)).to_date
      out << d << (d..d + @rng.rand(1..40))
    end
    since = round(near.call)
    out << (since < n ? Time.at(since)...now : now...Time.at(since)) if since != n
    out << (now...Time.at(n + @rng.rand(1..9) * 3600))
    PHRASES.sample(18, random: @rng).each { (r = Acute.parse(_1, **opts)) && out << r }
    out
  end

  def check(x, opts)
    @checked += 1
    want = expected(x, opts[:zone])
    # a day the zone skipped, such as Dec 30, 2011 in Apia, is no time at all
    return assert_raises(ArgumentError) { Acute.describe(x, **opts) } if want[:value].uniq.size == 1 && !want[:instant]
    text = Acute.describe(x, **opts)
    r = Acute.parse(text, **opts.except(:style))
    got = r && !r.ambiguous? && (want[:instant] ? [r.time.to_i] : [r.begin&.to_i, r.end&.to_i])
    return if got == want[:value]
    @misread << "#{show(x)} #{opts[:zone]} now=#{opts[:now].to_i} #{opts.values_at(:locale, :context, :style)} " \
                 "→ #{text.inspect} → #{r ? [r.begin, r.end, r.alternatives.size].inspect : 'nil'}"
  end

  def expected(x, zone)
    case x
    when Acute::Result then x.instant? ? { instant: true, value: [x.time.to_i] } : { value: [x.begin&.to_i, x.end&.to_i] }
    when Time then { instant: true, value: [x.to_i] }
    when Date then { value: days(zone, x, x + 1) }
    when Range
      return { value: days(zone, x.begin, x.end + 1) } if Date === x.begin
      { value: [x.begin&.to_i, x.end&.to_i] }
    end
  end

  def days(zone, a, b)
    z = Acute::Zone.for(zone)
    [a, b].map { z.local_to_utc((_1.jd - 2_440_588) * DAY, Struct.new(:dst).new) }
  end

  def show(x) = Acute::Result === x ? "Result(#{x.text.inspect})" : x.inspect

  def durations
    500.times do
      parts = { years: 3, months: 11, weeks: 5, days: 9, business_days: 4, hours: 40, minutes: 200, seconds: 9000 }
              .select { @rng.rand < 0.35 }.transform_values { @rng.rand(1.._1) }
      parts = { minutes: @rng.rand(1..500) } if parts.empty?
      parts[:seconds] += Rational(@rng.rand(1..99), 100) if parts[:seconds] && @rng.rand < 0.2
      d = Acute::Duration.new(**parts)
      @checked += 1
      back = Acute.duration(Acute.describe(d))
      @misread << "#{d.iso8601} → #{Acute.describe(d).inspect} → #{back&.iso8601.inspect}" unless same?(d, back)
    end
  end

  def same?(d, back)
    return false unless back
    clock = %i[hours minutes seconds]
    secs = ->(p) { p.fetch(:hours, 0) * 3600 + p.fetch(:minutes, 0) * 60 + p.fetch(:seconds, 0) }
    d.parts.except(*clock) == back.parts.except(*clock) && secs.(d.parts) == secs.(back.parts)
  end

  def transitions(zone)
    tz = TZInfo::Timezone.get(zone)
    tz.transitions_up_to(Time.utc(2090), Time.utc(1960)).map { _1.at.to_i }
  rescue TZInfo::InvalidTimezoneIdentifier
    []
  end

  def epoch(y1, y2) = @rng.rand(Time.utc(y1).to_i..Time.utc(y2).to_i)

  def round(t) = t - t % [60, 900, 3600].sample(random: @rng)
end
