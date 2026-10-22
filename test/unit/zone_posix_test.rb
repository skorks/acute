require_relative "../test_helper"

# D47 checked against an independent source: the system zoneinfo's TZif files, their explicit transitions and
# the POSIX TZ footer that gives the rule after the last of them. ACUTE_ZONE_SWEEP=full checks every zone and
# year; by default a sample keeps it fast.
class ZonePosixTest < Minitest::Test
  cover "Acute::Zone*"
  Notes = Struct.new(:dst)

  DIR = "/usr/share/zoneinfo".freeze
  FULL = ENV["ACUTE_ZONE_SWEEP"] == "full"
  FROM = Time.utc(2040).to_i
  TO = Time.utc(2101).to_i
  # Palestine's DST breaks for Ramadan through 2086, but tzinfo-data's changes stop in 2076, and D47 finds no
  # yearly rule among its last ones, so acute keeps standard time after 2076
  KNOWN = %w[Asia/Gaza Asia/Hebron].freeze

  # A POSIX TZ string, RFC 9636 section 3.3: std offset [dst [offset] ,start[/time],end[/time]]
  module Posix
    NAME = /<[^>]*>|[A-Za-z]+/
    OFFSET = /[+-]?\d+(?::\d+){0,2}/
    RULE = %r{(?:J\d+|\d+|M\d+\.\d\.\d)(?:/#{OFFSET})?}

    module_function

    def parse(footer)
      m = /\A(#{NAME})(#{OFFSET})(?:(#{NAME})(#{OFFSET})?,(#{RULE}),(#{RULE}))?\z/o.match(footer) or raise "bad footer #{footer}"
      std = [-seconds(m[2]), name(m[1])]
      return { std: } unless m[3]
      { std:, dst: [m[4] ? -seconds(m[4]) : std[0] + 3600, name(m[3])], start: rule(m[5]), end: rule(m[6]) }
    end

    def name(s) = s.delete("<>")

    def seconds(s)
      sign = s.start_with?("-") ? -1 : 1
      h, mi, se = s.delete("+-").split(":").map(&:to_i)
      sign * (h * 3600 + (mi || 0) * 60 + (se || 0))
    end

    def rule(s)
      date, time = s.split("/")
      [date, time ? seconds(time) : 7200]
    end

    # Days since the epoch of the rule's date in year y
    def day(date, y)
      jan1 = Acute::Calendar.days_from_civil(y, 1, 1)
      leap = Acute::Calendar.days_in_month(y, 2) == 29
      case date
      when /\AJ(\d+)\z/ then jan1 + $1.to_i - 1 + (leap && $1.to_i > 59 ? 1 : 0)
      when /\A(\d+)\z/ then jan1 + $1.to_i
      else
        mo, w, d = date.delete("M").split(".").map(&:to_i)
        first = Acute::Calendar.days_from_civil(y, mo, 1)
        n = first + (d - Acute::Calendar.weekday(first)) % 7 + 7 * (w - 1)
        n -= 7 while n >= first + Acute::Calendar.days_in_month(y, mo)
        n
      end
    end

    # [epoch, offset, abbreviation] for each change the rule makes in years
    def changes(tz, years)
      return [] unless tz[:dst]
      years.flat_map do |y|
        [[tz[:start], tz[:std], tz[:dst]], [tz[:end], tz[:dst], tz[:std]]].map do |(date, time), before, after|
          [day(date, y) * 86_400 + time - before[0], *after]
        end
      end.sort_by!(&:first)
    end
  end

  # A TZif v2+ file: its 64-bit transitions as [epoch, offset, abbreviation], and its footer
  def tzif(path)
    data = File.binread(path)
    return unless data.start_with?("TZif") && data[4] >= "2"
    isut, isstd, leap, time, type, char = data.unpack("@20N6")
    v2 = 44 + time * 5 + type * 6 + char + leap * 8 + isstd + isut
    isut, isstd, leap, time, type, char = data.unpack("@#{v2 + 20}N6")
    at = v2 + 44
    ats = data.unpack("@#{at}q>#{time}")
    kinds = data.unpack("@#{at + time * 8}C#{time}")
    types = (0...type).map { data.unpack("@#{at + time * 9 + _1 * 6}l>CC") }
    chars = data.byteslice(at + time * 9 + type * 6, char)
    footer_at = at + time * 9 + type * 6 + char + leap * 12 + isstd + isut
    trans = ats.zip(kinds).map { |t, k| [t, types[k][0], chars[types[k][2]..].unpack1("Z*")] }
    [trans, data.byteslice(footer_at..).strip]
  end

  # The system's changes, then its footer's after the last of them, to TO; nil without a footer
  def oracle(name)
    path = File.join(DIR, name)
    return unless File.file?(path) && (file = tzif(path)) && !file[1].empty?
    trans, footer = file
    tz = Posix.parse(footer)
    last = trans.empty? ? -Float::INFINITY : trans[-1][0]
    first_year = trans.empty? ? 2039 : [Time.at(last).utc.year, 2039].max
    rule = Posix.changes(tz, first_year..2101).select { _1[0] > last && _1[0] < TO }
    [[[-Float::INFINITY, *tz[:std]], *trans, *rule], tz] # before any change: irrelevant from 2040
  end

  def offset(changes, epoch)
    i = changes.bsearch_index { _1[0] > epoch } || changes.size
    changes[i - 1]
  end

  def system_version = File.foreach(File.join(DIR, "tzdata.zi")).first[/version (\S+)/, 1]

  # Compatible local_to_utc against the oracle: a repeated wall time takes the earlier instant, a skipped one
  # moves forward by the gap
  def expected_utc(changes, local)
    o1 = offset(changes, local - 86_400)[1]
    o2 = offset(changes, local + 86_400)[1]
    return [local - o1, nil] if o1 == o2
    ok1 = offset(changes, local - o1)[1] == o1
    ok2 = offset(changes, local - o2)[1] == o2
    if ok1 && ok2 then [local - o1, :dst_repeated_time]
    elsif ok1 then [local - o1, nil]
    elsif ok2 then [local - o2, nil]
    else [local - o1, :dst_skipped_time]
    end
  end

  def mismatches(name, changes)
    zone = Acute::Zone.for(name)
    window = changes.each_cons(2).select { |a, b| b[0].between?(FROM, TO - 1) && a[1] != b[1] }
    window = window.each_slice(9).map(&:first) unless FULL
    probes = window.flat_map { |_, b| (-1..1).map { b[0] + _1 } } + [FROM, TO - 1]
    locals = window.flat_map { |a, b| [a[1], b[1]].flat_map { |o| (-1..1).map { b[0] + o + _1 } } }
    wrong = probes.filter_map do |epoch|
      want = offset(changes, epoch)
      got = [zone.offset_at(epoch), zone.abbreviation_at(epoch)]
      [name, epoch, want[1..], got] unless got == want[1..]
    end
    wrong + locals.filter_map do |local|
      notes = Notes.new
      got = [zone.local_to_utc(local, notes), notes.dst]
      want = expected_utc(changes, local)
      [name, :local, local, want, got] unless got == want
    end
  end

  def test_offsets_and_wall_times_match_the_system_zoneinfo_from_2040_to_2100
    skip "no #{DIR}" unless File.directory?(DIR)
    names = Acute::Tables::ZONES.keys.sort
    same_release = system_version == Acute::TZDATA
    oracles = names.filter_map { |n| (o = oracle(n)) && [n, *o] }
    dst, fixed = oracles.partition { |_, _, tz| tz[:dst] }
    fixed = fixed.each_slice(10).map(&:first) unless FULL
    # A different release may have changed a rule: such a zone is skipped where the footer's 2040 disagrees
    # with acute's own data (tzinfo-data, of Acute::TZDATA), which runs explicitly to 2076
    skipped, checked = (dst + fixed).partition do |name, changes, _|
      next false if same_release
      tz = TZInfo::DataSources::RubyDataSource.new.get_timezone_info(name).create_timezone
      (FROM..Time.utc(2041).to_i).step(86_400).any? { tz.period_for_utc(Time.at(_1).utc).observed_utc_offset != offset(changes, _1)[1] }
    end
    wrong = checked.flat_map { |name, changes, _| KNOWN.include?(name) ? [] : mismatches(name, changes) }
    puts "\nzone sweep: #{dst.size} DST, #{fixed.size} fixed, #{skipped.size} skipped (system #{system_version})" if FULL
    assert_empty wrong.first(20)
    assert_operator checked.size, :>, 50
  end

  def test_posix_rules
    tz = Posix.parse("<-02>2<-01>,M3.5.0/-1,M10.5.0/0")
    assert_equal({ std: [-7200, "-02"], dst: [-3600, "-01"], start: ["M3.5.0", -3600], end: ["M10.5.0", 0] }, tz)
    assert_equal [Time.utc(2026, 3, 29, 1).to_i, Time.utc(2026, 10, 25, 1).to_i], Posix.changes(tz, [2026]).map(&:first)
    assert_equal Acute::Calendar.days_from_civil(2028, 3, 1), Posix.day("J60", 2028)
    assert_equal Acute::Calendar.days_from_civil(2028, 2, 29), Posix.day("59", 2028)
    assert_equal({ std: [19_800, "IST"] }, Posix.parse("IST-5:30"))
  end
end
