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
      (probes + [Time.utc(1900).to_i, Time.utc(2199, 7).to_i]).each do |epoch|
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

  def test_accepts_a_tzinfo_zone_and_shares_one_table
    assert_same Acute::Zone.for("Asia/Tokyo"), Acute::Zone.for(TZInfo::Timezone.get("Asia/Tokyo"))
    assert Acute::Zone.for("Asia/Tokyo").frozen?
  end

  def test_rejects_unknown_zones
    assert_raises(ArgumentError) { Acute::Zone.for("Mars/Olympus") }
    assert_raises(ArgumentError) { Acute::Zone.for(5) }
  end
end
