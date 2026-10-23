require_relative "../test_helper"

class ZoneTest < Minitest::Test
  cover "Acute::Zone*"
  Notes = Struct.new(:dst)

  def local(y, mo, d, h, mi) = Acute::Calendar.days_from_civil(y, mo, d) * 86_400 + h * 3600 + mi * 60

  def resolve(zone, *wall)
    notes = Notes.new
    utc = Acute::Zone.for(zone).local_to_utc(local(*wall), notes)
    [Time.at(utc, in: TZInfo::Timezone.get(zone)).strftime("%F %R %:z"), notes.dst]
  end

  # The release the tables were generated from (Gemfile.lock), whatever source tzinfo would pick itself
  TZDATA = TZInfo::DataSources::RubyDataSource.new

  # tzinfo-data's transitions run to 2076; D47 carries the shipped ones on, so they meet it at every one
  def test_every_zone_matches_tzinfo_data_either_side_of_every_transition
    assert_equal TZInfo::Data::Version::TZDATA, Acute::TZDATA
    names = TZDATA.timezone_identifiers
    assert_equal names.sort, (Acute::Tables::ZONES.keys + Acute::Tables::ZONE_LINKS.keys).sort
    names.each do |name|
      zone = Acute::Zone.for(name)
      tz = TZDATA.get_timezone_info(name).create_timezone
      probes = tz.transitions_up_to(Time.utc(2200), Time.utc(1800)).flat_map { |t| [t.timestamp_value - 1, t.timestamp_value] }
      (probes << Time.utc(1800).to_i).each do |epoch|
        period = tz.period_for_utc(Time.at(epoch).utc)
        assert_equal [period.observed_utc_offset, period.abbreviation], [zone.offset_at(epoch), zone.abbreviation_at(epoch)],
                     "#{name} #{epoch}"
      end
    end
  end

  # The next change of offset, skipping transitions that change only the abbreviation or DST flag
  def test_next_change_matches_tzinfo_data_before_every_transition
    limit = Time.utc(2200).to_i
    wrong = TZDATA.timezone_identifiers.flat_map do |name|
      zone = Acute::Zone.for(name)
      trans = TZDATA.get_timezone_info(name).create_timezone.transitions_up_to(Time.utc(2200), Time.utc(1800))
      trans.each_index.filter_map do |k|
        before = trans[k].previous_offset.observed_utc_offset
        expected = trans[k..].find { |t| t.offset.observed_utc_offset != before }&.timestamp_value
        got = zone.next_change(trans[k].timestamp_value - 1)
        [name, k] unless expected ? got == expected : got.nil? || got >= limit
      end
    end
    assert_empty wrong
    assert_nil Acute::Zone.for("Asia/Kolkata").next_change(Time.utc(2026).to_i)
    assert_nil Acute::Zone.for("+05:30").next_change(0)
  end

  # tzinfo's periods for a wall time: none in a gap, two in an overlap. A gap's instants come from the
  # transition whose wall-clock jump holds it: compatible and :later keep the old offset, :earlier the new.
  def tzinfo_local_to_utc(tz, trans, local, policy)
    periods = tz.periods_for_local(Time.at(local).utc)
    case periods.size
    when 1 then [local - periods[0].observed_utc_offset, nil]
    when 2
      first, last = periods.map { local - _1.observed_utc_offset }.sort
      [policy == :later ? last : first, :dst_repeated_time]
    else
      t = trans.find { local.between?(_1.timestamp_value + _1.previous_offset.observed_utc_offset, _1.timestamp_value + _1.offset.observed_utc_offset - 1) }
      [local - (policy == :earlier ? t.offset : t.previous_offset).observed_utc_offset, :dst_skipped_time]
    end
  end

  POLICIES = [nil, :earlier, :later].freeze

  # Wall times a second either side of each change, in the old offset and the new: New York's gap and overlap,
  # Lord Howe's half-hour DST, Moscow's standard offset changing (2011, 2014), Apia skipping a whole day (2011),
  # São Paulo's southern summer
  def test_local_to_utc_matches_tzinfo_data_either_side_of_every_transition
    wrong = %w[America/New_York Australia/Lord_Howe Europe/Moscow Pacific/Apia America/Sao_Paulo].flat_map do |name|
      zone = Acute::Zone.for(name)
      tz = TZDATA.get_timezone_info(name).create_timezone
      trans = tz.transitions_up_to(Time.utc(2200), Time.utc(1800))
      locals = trans.flat_map do |t|
        [t.previous_offset, t.offset].flat_map { |o| (-1..1).map { t.timestamp_value + o.observed_utc_offset + _1 } }
      end
      locals.uniq.product(POLICIES).filter_map do |local, policy|
        notes = Notes.new
        got = [zone.local_to_utc(local, notes, policy), notes.dst]
        want = tzinfo_local_to_utc(tz, trans, local, policy)
        [name, Time.at(local).utc.strftime("%F %T"), policy, got, want] unless got == want
      end
    end
    assert_empty wrong
  end

  def test_known_names_and_inspect
    assert Acute::Zone.known?("America/New_York")
    assert Acute::Zone.known?("US/Eastern")
    refute Acute::Zone.known?("Mars/Olympus")
    refute Acute::Zone.known?("+05:00")
    assert_equal "#<Acute::Zone US/Eastern>", Acute::Zone.for("US/Eastern").inspect
  end

  def test_new_york_fall_back_takes_the_earlier_time
    assert_equal ["2026-11-01 01:30 -04:00", :dst_repeated_time], resolve("America/New_York", 2026, 11, 1, 1, 30)
    assert_equal ["2026-11-01 02:00 -05:00", nil], resolve("America/New_York", 2026, 11, 1, 2, 0)
  end

  def test_new_york_spring_forward_moves_forward_by_the_gap
    assert_equal ["2027-03-14 03:30 -04:00", :dst_skipped_time], resolve("America/New_York", 2027, 3, 14, 2, 30)
    assert_equal ["2027-03-14 01:59 -05:00", nil], resolve("America/New_York", 2027, 3, 14, 1, 59)
  end

  def test_sydney_southern_hemisphere
    assert_equal ["2026-04-05 02:30 +11:00", :dst_repeated_time], resolve("Australia/Sydney", 2026, 4, 5, 2, 30)
    assert_equal ["2026-10-04 03:15 +11:00", :dst_skipped_time], resolve("Australia/Sydney", 2026, 10, 4, 2, 15)
  end

  def test_kolkata_has_a_half_hour_offset_and_no_dst
    assert_equal ["2026-10-17 09:00 +05:30", nil], resolve("Asia/Kolkata", 2026, 10, 17, 9, 0)
  end

  def test_lord_howe_shifts_by_half_an_hour
    assert_equal ["2026-04-05 01:45 +11:00", :dst_repeated_time], resolve("Australia/Lord_Howe", 2026, 4, 5, 1, 45)
    assert_equal ["2026-10-04 02:45 +11:00", :dst_skipped_time], resolve("Australia/Lord_Howe", 2026, 10, 4, 2, 15)
  end

  def test_fixed_offsets
    zone = Acute::Zone.for("-03:30")
    assert_equal(-12_600, zone.offset_at(0))
    assert_equal "-03:30", zone.abbreviation_at(0)
    assert_equal 12_600, zone.local_to_utc(0, Notes.new)
  end

  def test_local_mean_time_before_standard_time
    ny = Acute::Zone.for("America/New_York")
    assert_equal(-17_762, ny.offset_at(Time.utc(1530).to_i))
    assert_equal(-18_000, ny.offset_at(Time.utc(1890).to_i))
  end

  def test_fixed_from_seconds_is_the_named_offset
    assert_same Acute::Zone.for("+05:45"), Acute::Zone.fixed(20_700)
    assert_equal "-03:30", Acute::Zone.fixed(-12_600).name
  end

  def test_steady_offset_is_nil_within_a_day_of_a_transition
    zone = Acute::Zone.for("America/New_York")
    fall_back = Time.utc(2026, 11, 1, 6).to_i
    assert_equal(-14_400, zone.steady_offset(fall_back - 3 * 86_400, fall_back - 2 * 86_400))
    assert_nil zone.steady_offset(fall_back - 3 * 86_400, fall_back - 3600)
    assert_nil zone.steady_offset(fall_back + 3600, fall_back + 2 * 86_400)
    assert_equal(-18_000, zone.steady_offset(fall_back + 2 * 86_400, fall_back + 3 * 86_400))
  end

  def test_accepts_a_tzinfo_zone_and_shares_one_table
    assert_same Acute::Zone.for("Asia/Tokyo"), Acute::Zone.for(TZInfo::Timezone.get("Asia/Tokyo"))
    assert_predicate Acute::Zone.for("Asia/Tokyo"), :frozen?
  end

  # A zone from an app's own tzinfo data source, under a name acute doesn't ship
  Custom = Struct.new(:identifier, :tz) do
    def transitions_up_to(...) = tz.transitions_up_to(...)
    def period_for_utc(...) = tz.period_for_utc(...)
  end

  def test_a_tzinfo_zone_acute_does_not_know_is_built_from_its_own_data
    zone = Acute::Zone.for(Custom.new("Custom/Sydney", TZInfo::Timezone.get("Australia/Sydney")))
    sydney = Acute::Zone.for("Australia/Sydney")
    epochs = [Time.utc(1900), Time.utc(2026, 1), Time.utc(2026, 7), Time.utc(2150, 1), Time.utc(2150, 7)].map(&:to_i)
    assert_equal(epochs.map { sydney.offset_at(_1) }, epochs.map { zone.offset_at(_1) })
    assert_equal "Custom/Sydney", zone.name
    assert_equal 32_400, Acute::Zone.for(Custom.new("Custom/Nine", TZInfo::Timezone.get("Etc/GMT-9"))).offset_at(0)
    assert_equal "Custom/Sydney", parse("today", zone: Custom.new("Custom/Sydney", TZInfo::Timezone.get("Australia/Sydney"))).zone
  end

  def test_links_answer_as_their_target_under_their_own_name
    zone = Acute::Zone.for("US/Eastern")
    assert_equal "US/Eastern", zone.name
    assert_equal(-14_400, zone.offset_at(Time.utc(2026, 7).to_i))
  end

  # The nth (or, with -1, last) Sunday of a month, at hour o'clock UTC
  def sunday(y, m, nth, hour)
    days = (1..Date.new(y, m, -1).day).map { Date.new(y, m, _1) }.select(&:sunday?)
    Time.utc(y, m, days[nth > 0 ? nth - 1 : nth].day, hour).to_i
  end

  def test_d47_clock_changes_go_on_past_the_data_to_2200
    ny = Acute::Zone.for("America/New_York")
    sydney = Acute::Zone.for("Australia/Sydney")
    london = Acute::Zone.for("Europe/London")
    (2026..2199).each do |y|
      us_on = sunday(y, 3, 2, 7)
      us_off = sunday(y, 11, 1, 6)
      assert_equal [-18_000, -14_400, -14_400, -18_000], [ny.offset_at(us_on - 1), ny.offset_at(us_on), ny.offset_at(us_off - 1), ny.offset_at(us_off)], y
      au_off = sunday(y, 4, 1, 3 - 11 + 24) - 86_400
      au_on = sunday(y, 10, 1, 2 - 10 + 24) - 86_400
      assert_equal [39_600, 36_000, 36_000, 39_600], [sydney.offset_at(au_off - 1), sydney.offset_at(au_off), sydney.offset_at(au_on - 1), sydney.offset_at(au_on)], y
      assert_equal %w[GMT BST], [london.abbreviation_at(sunday(y, 3, -1, 1) - 1), london.abbreviation_at(sunday(y, 3, -1, 1))], y
    end
  end

  def test_d47_far_dates_follow_dst
    assert_equal "2079-07-04T12:00:00-04:00", parse("2079-07-04 12:00").iso8601
    assert_equal "2079-01-04T12:00:00-05:00", parse("2079-01-04 12:00").iso8601
    assert_equal "2150-01-04T12:00:00+11:00", parse("2150-01-04 12:00", zone: "Australia/Sydney").iso8601
    assert_equal "2150-07-04T12:00:00+10:00", parse("2150-07-04 12:00", zone: "Australia/Sydney").iso8601
  end

  def test_d47_a_zone_that_stopped_changing_its_clocks_stays_stopped
    mexico = Acute::Zone.for("America/Mexico_City")
    months = [1, 7]
    assert_equal [-21_600], [2030, 2100, 2199].flat_map { |y| months.map { mexico.offset_at(Time.utc(y, _1).to_i) } }.uniq
  end

  # Eastern US rules, as the changes a source holding exactly these years would list
  def us_changes(years)
    years.flat_map do |y|
      march = Acute::Calendar.days_from_civil(y, 3, 8)
      march += (0 - Acute::Calendar.weekday(march)) % 7
      nov = Acute::Calendar.days_from_civil(y, 11, 1)
      nov += (0 - Acute::Calendar.weekday(nov)) % 7
      [[march * 86_400 + 7200 + 18_000, -14_400, "EDT"], [nov * 86_400 + 7200 + 14_400, -18_000, "EST"]]
    end
  end

  def carried_on(years)
    ats, offsets, abbreviations = us_changes(years).transpose
    Acute::Zone.send(:recurring, ats, offsets, abbreviations, -18_000)
  end

  def test_d47_carries_on_only_from_two_rule_years_of_changes_that_run_past_2037
    assert_equal 2 * (2200 - 2039), carried_on(2031..2038).size
    assert_empty carried_on(2023..2030)
    fifteen = us_changes(2031..2038).drop(1).transpose
    assert_empty Acute::Zone.send(:recurring, *fifteen.first(3), -18_000)
  end

  def test_d47_an_odd_rule_in_the_oldest_of_the_years_is_no_yearly_rule
    ats, offsets, abbreviations = us_changes(2031..2038).transpose
    ats[0] += 3600
    ats[1] += 3600
    assert_empty Acute::Zone.send(:recurring, ats, offsets, abbreviations, -18_000)
  end

  def test_d47_a_missing_year_among_the_changes_is_no_yearly_rule
    assert_empty carried_on([2031, 2032, 2033, 2034, 2036, 2037, 2038, 2039])
  end

  def test_rejects_unknown_zones
    e = assert_raises(Acute::OptionError) { Acute::Zone.for("Mars/Olympus") }
    assert_equal ["unknown zone \"Mars/Olympus\"", :zone, "Mars/Olympus"], [e.message, e.option, e.value]
    assert_raises(ArgumentError) { Acute::Zone.for(5) }
    %w[+24:00 +99:99 -05:60].each { |z| assert_raises(ArgumentError, z) { Acute::Zone.for(z) } }
    assert_equal 86_340, Acute::Zone.for("+23:59").offset_at(0)
  end

  def test_d44_an_iana_name_in_the_text_keeps_its_clock_changes
    assert_equal "2006-05-12 16:59:59 +00:00", wall(parse("2006-05-12 12:59:59 America/New_York", zone: "UTC").begin)
    assert_equal "2026-10-17 19:00:03 -04:00", wall(parse("01:00:03.12345 europe/amsterdam").begin)
    assert_equal "2026-10-17 15:23:42 -04:00", wall(parse("T13:23:42 America/Denver").begin)
    assert_equal "2026-10-17 16:00:00 -04:00", wall(parse("3pm America/Indiana/Knox").begin)
    assert_raises(Acute::ParseError) { parse("3pm Europe/Atlantis") }
  end

  def test_d47_a_named_zone_records_its_clock_change
    r = parse("nov 1 2026 1:30am America/Chicago")
    assert_equal "2026-11-01 01:30:00 -05:00", wall(r.time)
    assert_includes codes(r), :dst_repeated_time
    r = parse("march 8 2026 2:30am America/Chicago")
    assert_equal "2026-03-08 04:30:00 -04:00", wall(r.time)
    assert_includes codes(r), :dst_skipped_time
    refute_includes codes(parse("nov 2 2026 1:30am America/Chicago")), :dst_repeated_time
  end

  def test_d47_a_named_zone_follows_the_dst_option
    assert_equal "2026-11-01 02:30:00 -05:00", wall(parse("nov 1 2026 1:30am America/Chicago", dst: :later).time)
    e = assert_raises(Acute::ParseError) { parse("nov 1 2026 1:30am America/Chicago", dst: :reject) }
    assert_equal :dst_repeated_time, e.code
  end

  def test_d44_a_us_zone_without_standard_or_daylight_follows_the_clock_change
    assert_equal "2022-03-13 04:00:00 +00:00", wall(parse("2022-03-12 23:00 ET", zone: "UTC").begin)
    assert_equal "2022-03-14 03:00:00 +00:00", wall(parse("2022-03-13 23:00 ET", zone: "UTC").begin)
    assert_equal "2026-10-18 01:00:00 -04:00", wall(parse("10pm pacific time").begin)
    assert_equal "2026-10-17 16:00:00 -04:00", wall(parse("3pm central").begin)
  end

  def test_d44_a_zone_in_the_text_also_reckons_the_day
    r = parse("tomorrow, 10pm pacific", now: "2012-05-19T00:00")
    assert_equal "2012-05-20 01:00:00 -04:00", wall(r.begin)
  end

  def test_more_fixed_abbreviations
    assert_equal "2010-02-17 23:14:12 +00:00", wall(parse("2:14:12 MSK", now: "2010-02-17T10:00", zone: "UTC").begin)
    assert_equal "2026-10-17 18:00:00 -04:00", wall(parse("noon HST").begin)
  end

  def test_d45_each_end_of_a_range_keeps_its_offset
    r = parse("Nov 1, 2026, 1am EDT – Nov 1, 2026, 1:30am EST")
    assert_equal ["2026-11-01 01:00:00 -04:00", "2026-11-01 01:30:00 -05:00"], [wall(r.begin), wall(r.end)]
    r = parse("2026-11-01T01:00:00-04:00 – 2026-11-01T01:30:00-05:00")
    assert_equal 5400, r.end - r.begin
    r = parse("Nov 1, 2026, 1:50am EDT – Nov 1, 2026, 1:10am EST")
    assert_equal 1200, r.end - r.begin
  end

  # D47 past tzinfo-data's 2076: Cairo's summer ends on the last Thursday of October at 24:00, which in 2080 is
  # Friday 1 November
  def test_a_change_at_24_00_is_carried_on_across_the_month_end
    cairo = Acute::Zone.for("Africa/Cairo")
    change = Time.utc(2080, 10, 31, 21).to_i
    assert_equal [10_800, 7200], [cairo.offset_at(change - 1), cairo.offset_at(change)]
    assert_equal 10_800, cairo.offset_at(Time.utc(2199, 7, 1).to_i)
  end
end
