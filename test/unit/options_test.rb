require_relative "../test_helper"
require "stringio"
require_relative "../../lib/acute/cli"

# The context options D47 settled: strict:, dst:, holidays:, business_days: and year_bias:
class OptionsTest < Minitest::Test
  AT = { now: "2026-10-17T14:00", zone: NY }.freeze

  # Days off on Monday 19 October and Thanksgiving moved to 20 November
  class Office
    def holiday?(date) = date == Date.new(2026, 10, 19)

    def named(name, year) = name == :thanksgiving ? Date.new(year, 11, 20) : nil
  end

  class SixDays
    def business_day?(date) = !date.sunday?
  end

  def test_d47_strict_false_skips_unknown_words
    r = parse("lunch with bob tomorrow at noon please", strict: false)
    assert_equal "2026-10-18 12:00:00 -04:00", wall(r.time)
    assert_equal "lunch with bob tomorrow at noon please", r.text
    assert_equal "tomorrow at noon", r.matched
    assert_equal [:unknown_words_skipped], codes(r)
  end

  def test_d22_strict_is_the_default
    assert_nil Acute.parse("lunch with bob tomorrow at noon", **AT)
    assert_equal "tomorrow", Acute.parse("tomorrow", **AT, strict: false).matched
    assert_empty codes(parse("tomorrow", strict: false))
  end

  def test_d47_strict_false_without_a_time_keeps_the_unknown_word_error
    e = assert_raises(Acute::ParseError) { parse("blah blah", strict: false) }
    assert_equal :unknown_word, e.code
  end

  def test_d47_strict_false_works_everywhere
    p = Acute.with(**AT, strict: false)
    assert_equal Date.new(2026, 10, 18), p.parse("tomorrow ok").date
    assert_equal Date.new(2026, 10, 18), p.read("tomorrow ok").date
    assert_equal Date.new(2026, 10, 18), p.extract("see you tomorrow").mentions[0].value.date
    assert_equal :match, p.verify("tomorrow ok", "2026-10-18").status
    assert_equal "tomorrow", p.describe(Date.new(2026, 10, 18))
    assert_raises(ArgumentError) { Acute.parse("today", strict: nil) }
  end

  def test_d23_dst_compatible_is_the_default
    r = parse("march 8 2026 2:30am")
    assert_equal "2026-03-08 03:30:00 -04:00", wall(r.time)
    assert_equal [:dst_skipped_time], codes(r)
    assert_equal "2026-03-08 03:30:00 -04:00", wall(parse("march 8 2026 2:30am", dst: :compatible).time)
  end

  def test_d47_dst_earlier_and_later
    assert_equal "2026-03-08 01:30:00 -05:00", wall(parse("march 8 2026 2:30am", dst: :earlier).time)
    assert_equal "2026-03-08 03:30:00 -04:00", wall(parse("march 8 2026 2:30am", dst: :later).time)
    assert_equal "2026-11-01 01:30:00 -04:00", wall(parse("nov 1 2026 1:30am", dst: :earlier).time)
    later = parse("nov 1 2026 1:30am", dst: "later")
    assert_equal "2026-11-01 01:30:00 -05:00", wall(later.time)
    assert_empty codes(later), "a policy the caller chose is not an assumption"
  end

  def test_d47_dst_reject
    assert_nil Acute.parse("nov 1 2026 1:30am", **AT, dst: :reject)
    e = assert_raises(Acute::ParseError) { parse("nov 1 2026 1:30am", dst: :reject) }
    assert_equal :dst_repeated_time, e.code
    assert_match(/happens twice/, e.message)
    e = assert_raises(Acute::ParseError) { parse("march 8 2026 2:30am", dst: :reject) }
    assert_equal :dst_skipped_time, e.code
    assert_equal "2026-11-01 03:30:00 -05:00", wall(parse("nov 1 2026 3:30am", dst: :reject).time)
    assert_raises(ArgumentError) { Acute.parse("today", dst: :nearest) }
  end

  def test_d47_dst_reject_drops_alternatives_on_a_changing_wall_time
    assert_equal ["2026-11-01 01:30:00 -04:00"], alt_walls(parse("1:30", now: "2026-10-31T14:00"))
    r = parse("1:30", now: "2026-10-31T14:00", dst: :reject)
    assert_equal "2026-11-01 13:30:00 -05:00", wall(r.time)
    assert_empty r.alternatives
  end

  def test_d23_year_bias_moves_the_two_digit_window
    assert_equal 1976, parse("1/2/76").time.year
    assert_equal 2075, parse("1/2/75").time.year
    assert_equal 2076, parse("1/2/76", year_bias: 10).time.year
    assert_equal 2030, parse("1/2/30", year_bias: 90).time.year
    assert_equal 1930, parse("1/2/30", year_bias: 99).time.year
    assert_equal 2110, parse("the 10s", year_bias: 0).begin.year
  end

  def test_d47_holidays_object_names_days_and_takes_days_off
    o = Office.new
    assert_equal Date.new(2026, 11, 20), parse("thanksgiving", holidays: o).date
    assert_equal Date.new(2026, 11, 26), parse("thanksgiving").date
    assert_equal Date.new(2026, 12, 25), parse("christmas", holidays: o).date, "the built-in formulas stay"
    assert_equal "2026-10-21 14:00:00 -04:00", wall(parse("3 business days from now").time)
    assert_equal "2026-10-22 14:00:00 -04:00", wall(parse("3 business days from now", holidays: o).time)
    assert_equal Date.new(2026, 10, 20), parse("next business day", holidays: o).date
  end

  def test_d47_built_in_holidays_are_not_days_off
    assert_equal Date.new(2026, 12, 25), parse("next business day", now: "2026-12-24T14:00").date
  end

  def test_d47_business_days_object
    six = SixDays.new
    assert_equal Date.new(2026, 10, 19), parse("next business day", business_days: six).date
    assert_equal "2026-10-15 14:00:00 -04:00", wall(parse("2 business days ago", business_days: six).time)
    assert_equal Date.new(2026, 11, 3), parse("the 2nd business day of november", business_days: six).date
    assert_equal Date.new(2026, 10, 27), parse("3 business days after friday", business_days: six).date
    assert_equal Date.new(2026, 10, 28), parse("3 business days after friday").date
  end

  def test_d47_objects_are_checked_and_not_frozen
    assert_raises(ArgumentError) { Acute.parse("today", holidays: Object.new) }
    assert_raises(ArgumentError) { Acute.parse("today", business_days: Object.new) }
    o = Office.new
    p = Acute.with(**AT, holidays: o)
    refute o.frozen?
    assert p.frozen?
    refute Ractor.shareable?(p)
    assert_equal Date.new(2026, 11, 20), p.parse("thanksgiving").date
    assert Ractor.shareable?(Acute.with(**AT, dst: :later, strict: false, year_bias: 10))
  end

  def test_d47_a_holidays_gem_region_needs_the_gem
    skip "the holidays gem is installed" if Gem::Specification.find_all_by_name("holidays").any?
    e = assert_raises(ArgumentError) { Acute.parse("today", holidays: :us) }
    assert_match(/holidays gem/, e.message)
  end

  # A stand-in for the gem, with the two calls acute makes
  module FakeGem
    DAYS = [{ date: Date.new(2026, 11, 26), name: "Thanksgiving" }, { date: Date.new(2026, 12, 25), name: "Christmas Day" },
            { date: Date.new(2026, 10, 12), name: "Columbus Day" }].freeze

    def self.on(date, *regions) = regions == [:us] ? DAYS.select { _1[:date] == date } : []

    def self.between(from, to, *regions) = regions == [:us] ? DAYS.select { _1[:date].between?(from, to) } : []
  end

  def test_d47_a_holidays_gem_region
    Object.const_set(:Holidays, FakeGem)
    assert_equal Date.new(2026, 12, 25), parse("christmas", holidays: "us").date
    assert_equal Date.new(2026, 11, 27), parse("the day after thanksgiving", holidays: [:us]).date
    assert_equal "2026-11-30 14:00:00 -05:00", wall(parse("3 business days from now", now: "2026-11-24T14:00", holidays: :us).time)
    assert Ractor.shareable?(Acute.with(**AT, holidays: :us))
  ensure
    Object.send(:remove_const, :Holidays) if Object.const_defined?(:Holidays)
  end

  def test_duration_takes_the_options
    assert_equal 10_800, Acute.duration("3 hours", **AT, strict: false).seconds
    assert_equal 5400, Acute.with(**AT, dst: :reject).duration("90 min").seconds
  end

  def test_cli_flags
    out = StringIO.new
    err = StringIO.new
    at = %w[--now 2026-10-17T14:00 --zone America/New_York]
    assert_equal 0, Acute::CLI.run(["--lenient", "--json", *at, "lunch tomorrow ok"], stdin: StringIO.new, stdout: out, stderr: err)
    assert_equal "unknown_words_skipped", JSON.parse(out.string)["assumptions"][0]["code"]
    out = StringIO.new
    assert_equal 1, Acute::CLI.run(["--dst", "reject", *at, "nov 1 2026 1:30am"], stdin: StringIO.new, stdout: out, stderr: err)
    assert_match(/happens twice/, err.string)
    out = StringIO.new
    assert_equal 0, Acute::CLI.run(["--year-bias", "10", *at, "1/2/76"], stdin: StringIO.new, stdout: out, stderr: err)
    assert_match(/2076/, out.string)
  end
end
