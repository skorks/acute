require_relative "../test_helper"

# D17, D47, D49: business days are counted, not stepped through, and one call counts at most 10,000 (T17)
class BusinessDaysTest < Minitest::Test
  NOW = Time.new(2026, 10, 21, 12, 0, 0, "-04:00")
  EPOCH = 2_440_588
  FIXED = [[1, 1], [7, 4], [11, 11], [12, 25]].freeze

  # A count past the budget is not a time, though its words may still be a duration
  def times(extraction) = extraction.mentions.select { _1.kind == :time }.map(&:text)

  def elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC).then do |t|
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - t
  end

  # The holidays gem's two calls, over a fixed set of days
  def with_gem(days)
    rows = days.map { { date: Date.jd(_1 + EPOCH), name: "Day" } }
    gem = Module.new
    gem.define_singleton_method(:between) { |from, to, *| rows.select { _1[:date].between?(from, to) } }
    gem.define_singleton_method(:on) { |date, *| rows.select { _1[:date] == date } }
    real = Object.send(:remove_const, :Holidays) if Object.const_defined?(:Holidays)
    Object.const_set(:Holidays, gem)
    yield
  ensure
    Object.send(:remove_const, :Holidays)
    Object.const_set(:Holidays, real) if real
  end

  def reference(d, n, off)
    step = n < 0 ? -1 : 1
    n.abs.times do
      d += step
      d += step while (d + 4) % 7 % 6 == 0 || off.include?(d)
    end
    d
  end

  def test_weekdays_agree_with_stepping_across_week_boundaries
    rng = Random.new(17)
    500.times do
      d = rng.rand(-30_000..30_000)
      n = [rng.rand(1..30), rng.rand(1..3000)].sample(random: rng) * [1, -1].sample(random: rng)
      assert_equal reference(d, n, []), Acute::Calendar.add_weekdays(d, n), "day #{d}, #{n} weekdays"
    end
  end

  def test_a_region_agrees_with_stepping_with_holidays_on_weekends_and_counting_back
    rng = Random.new(1717)
    today = NOW.to_date.jd - EPOCH
    off = Array.new(400) { today + rng.rand(-1500..1500) } + [today + 3, today + 4] # weekend days, and duplicates
    off += off.first(20)
    with_gem(off) do
      region = Acute::Holidays::Region.new([:us], :us)
      100.times do
        d = today + rng.rand(-400..400)
        n = rng.rand(-300..300)
        assert_equal reference(d, n, off), Acute::Holidays::RegionDays.new(region).add(d, n), "day #{d}, #{n} days"
      end
      t = Acute.parse("9 business days ago", now: NOW, zone: NY, holidays: :us).time
      assert_equal reference(today, -9, off), t.to_date.jd - EPOCH
    end
  end

  def test_the_counts_in_one_call_share_ten_thousand_days
    x = Acute.extract("in 6000 business days or in 6000 business days or in 4000 business days", now: NOW, zone: NY)
    assert_equal ["in 6000 business days", "in 4000 business days"], times(x)
    e = assert_raises(Acute::ParseError) { Acute.parse!("6000 business days after 6000 business days from now", now: NOW, zone: NY) }
    assert_equal :business_day_limit, e.code
    assert_equal "more than 10000 business days in one call is too many to count", e.message
  end

  def test_each_call_of_a_shared_parser_gets_its_own_budget
    parser = Acute.with(now: NOW, zone: NY)
    2.times { assert_equal 1, times(parser.extract("in 9000 business days or in 9000 business days")).size }
    assert Ractor.shareable?(parser)
  end

  def test_a_calendar_is_asked_about_at_most_ten_thousand_days_off_a_call
    asked = 0
    sundays = Object.new
    sundays.define_singleton_method(:business_day?) { |date| (asked += 1) && date.sunday? }
    x = Acute.extract("in 1000 business days or in 1000 business days", now: NOW, zone: NY, business_days: sundays)
    assert_equal ["in 1000 business days"], times(x)
    assert_operator asked, :<=, 20_000
  end

  def test_t17_four_kilobytes_of_counts_with_holidays_stays_fast
    text = ("in 9999 business days " * 200)[0, 4096]
    count = ->(holidays) { elapsed { assert_equal 1, times(Acute.extract(text, now: NOW, zone: NY, holidays: holidays)).size } }
    if Gem::Specification.find_all_by_name("holidays").any?
      require "holidays"
      assert_operator count.(:us), :<, 0.5
    else
      fixed = (1990..2080).flat_map { |y| FIXED.map { Date.new(y, *_1).jd - EPOCH } }
      with_gem(fixed) { assert_operator count.(:us), :<, 0.5 }
    end
    assert_operator count.(nil), :<, 0.5
  end
end
