require_relative "../test_helper"

class ZoneTest < Minitest::Test
  Notes = Struct.new(:dst)

  def local(y, mo, d, h, mi) = Acute::Calendar.days_from_civil(y, mo, d) * 86_400 + h * 3600 + mi * 60

  def resolve(zone, *wall)
    notes = Notes.new
    utc = Acute::Zone.for(zone).local_to_utc(local(*wall), notes)
    [Time.at(utc, in: TZInfo::Timezone.get(zone)).strftime("%F %R %:z"), notes.dst]
  end

  def test_offsets_match_tzinfo_either_side_of_every_transition
    %w[America/New_York Australia/Sydney Asia/Kolkata Australia/Lord_Howe Europe/London America/Sao_Paulo].each do |name|
      zone = Acute::Zone.for(name)
      tz = TZInfo::Timezone.get(name)
      probes = tz.transitions_up_to(Time.utc(2200), Time.utc(1900)).flat_map { |t| [t.timestamp_value - 1, t.timestamp_value] }
      (probes + [Time.utc(1900).to_i]).each do |epoch|
        period = tz.period_for_utc(Time.at(epoch).utc)
        assert_equal period.observed_utc_offset, zone.offset_at(epoch), "#{name} #{epoch}"
        assert_equal period.abbreviation, zone.abbreviation_at(epoch), "#{name} #{epoch}"
      end
    end
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

  # The nth (or, with -1, last) Sunday of a month, at hour o'clock UTC
  def sunday(y, m, nth, hour)
    days = (1..Date.new(y, m, -1).day).map { Date.new(y, m, _1) }.select(&:sunday?)
    Time.utc(y, m, days[nth > 0 ? nth - 1 : nth].day, hour).to_i
  end

  def test_d47_clock_changes_go_on_past_tzinfos_data_to_2200
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

  def test_rejects_unknown_zones
    assert_raises(ArgumentError) { Acute::Zone.for("Mars/Olympus") }
    assert_raises(ArgumentError) { Acute::Zone.for(5) }
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
end
