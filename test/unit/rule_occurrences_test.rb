require_relative "../test_helper"
require "json"

class RuleOccurrencesTest < Minitest::Test
  OPTS = { now: "2026-10-17T14:00", zone: NY }.freeze
  AFTER = Time.new(2026, 10, 17, 14, 0, 0, "-04:00")

  def rule(text, **opts) = Acute.recurrence(text, **OPTS, **opts) || flunk("no rule for #{text.inspect}")

  def walls(list) = list.map { wall(_1) }

  def dates(list) = list.map(&:iso8601)

  # R16

  def test_r16_a_timed_rule_gives_times_in_its_zone
    out = rule("every weekday at 9am").next(2, after: AFTER)
    assert_equal ["2026-10-19 09:00:00 -04:00", "2026-10-20 09:00:00 -04:00"], walls(out)
    assert(out.all? { Time === _1 })
  end

  def test_r16_a_rule_of_whole_days_gives_dates
    out = rule("every other friday").next(3, after: AFTER)
    assert_equal %w[2026-10-23 2026-11-06 2026-11-20], dates(out)
    assert(out.all? { Date === _1 })
  end

  def test_r16_next_gives_an_array_and_defaults_to_one_from_now
    out = rule("every 15 minutes").next
    assert_equal 1, out.size
    assert_operator out[0], :>, Time.now
    assert_equal [], rule("daily").next(0)
  end

  def test_r16_next_is_strictly_after_an_instant
    r = rule("every day at 9am")
    assert_equal ["2026-10-20 09:00:00 -04:00"], walls(r.next(after: Time.new(2026, 10, 19, 9, 0, 0, "-04:00")))
    assert_equal ["2026-10-19 09:00:00 -04:00"], walls(r.next(after: Time.new(2026, 10, 19, 8, 59, 59.5r, "-04:00")))
    assert_equal ["2026-10-19 09:00:00 -04:00"], walls(r.next(after: Time.utc(2026, 10, 19, 12, 59, 59)))
  end

  def test_r16_a_day_under_way_counts_and_a_date_means_after_it
    r = rule("every monday")
    assert_equal %w[2026-10-19], dates(r.next(after: Time.new(2026, 10, 19, 23, 0, 0, "-04:00")))
    assert_equal %w[2026-10-26], dates(r.next(after: Date.new(2026, 10, 19)))
    assert_equal ["2026-10-20 09:00:00 -04:00"], walls(rule("every day at 9am").next(after: Date.new(2026, 10, 19)))
  end

  def test_r16_between_includes_from_and_leaves_out_to
    r = rule("every day at 9am")
    out = r.between(Time.new(2026, 10, 19, 9, 0, 0, "-04:00"), Time.new(2026, 10, 21, 9, 0, 0, "-04:00"))
    assert_equal ["2026-10-19 09:00:00 -04:00", "2026-10-20 09:00:00 -04:00"], walls(out)
  end

  def test_r16_a_date_in_between_is_its_whole_day
    assert_equal %w[2026-10-19 2026-10-26], dates(rule("every monday").between(Date.new(2026, 10, 19), Date.new(2026, 10, 26)))
    out = rule("every day at 9am").between(Date.new(2026, 10, 20), Date.new(2026, 10, 21))
    assert_equal ["2026-10-20 09:00:00 -04:00", "2026-10-21 09:00:00 -04:00"], walls(out)
    # A day any of which falls in the window counts
    out = rule("every monday").between(Time.new(2026, 10, 19, 23, 0, 0, "-04:00"), Time.new(2026, 10, 26, 0, 0, 1, "-04:00"))
    assert_equal %w[2026-10-19 2026-10-26], dates(out)
    assert_equal [], rule("every monday").between(Time.new(2026, 10, 20, 0, 0, 0, "-04:00"), Time.new(2026, 10, 26, 0, 0, 0, "-04:00"))
  end

  def test_r16_each_is_lazy_and_starts_at_dtstart
    r = rule("every 15 minutes")
    e = r.each
    assert_kind_of Enumerator, e
    assert_equal ["2026-10-17 14:00:00 -04:00", "2026-10-17 14:15:00 -04:00"], walls(e.first(2))
    assert_equal ["2026-10-18 00:15:00 -04:00"], walls(r.each(after: Time.new(2026, 10, 18, 0, 0, 0, "-04:00")).first(1))
    assert_equal 1500, rule("every day at 9am").each.first(1500).size # R19's cap is for next and between
    seen = []
    five = rule("every other friday 5 times")
    assert_same(five, five.each { seen << _1 })
    assert_equal 5, seen.size
  end

  def test_r16_bad_arguments_raise
    r = rule("daily")
    assert_raises(ArgumentError) { r.next(-1) }
    assert_raises(ArgumentError) { r.next("3") }
    assert_raises(ArgumentError) { r.next(after: "tomorrow") }
    assert_equal %w[2026-10-18], dates(r.next(after: DateTime.new(2026, 10, 18, 12))) # 8am in New York
  end

  # R17: each RRULE part

  def test_r17_interval_counts_from_dtstart_not_from_after
    r = rule("every other friday")
    assert_equal %w[2026-11-06 2026-11-20], dates(r.next(2, after: Date.new(2026, 10, 30)))
    assert_equal %w[2026-10-20 2026-10-23], dates(rule("every 3 days").next(2, after: Date.new(2026, 10, 17)))
    assert_equal ["2026-10-17 16:00:00 -04:00"], walls(rule("every 2 hours").next(after: Time.new(2026, 10, 17, 15, 0, 0, "-04:00")))
  end

  def test_r17_a_huge_interval_is_one_step_a_period
    years = rule("every 99999999 years").each.first(2).map(&:year)
    assert_equal [2026, 100_002_025], years
  end

  def test_r17_byday_with_ordinals
    assert_equal %w[2026-11-12 2026-12-10 2027-01-14], dates(rule("every 2nd thursday").next(3, after: AFTER))
    assert_equal %w[2026-10-30 2026-11-27 2026-12-25], dates(rule("the last friday of every month").next(3, after: AFTER))
    assert_equal %w[2026-10-23 2026-11-20 2026-12-18], dates(rule("the second to last friday of every month").next(3, after: AFTER))
    assert_equal %w[2026-10-27 2026-11-10 2026-11-24], dates(rule("the 2nd and 4th tuesday of every month").next(3, after: AFTER))
  end

  def test_r17_bymonthday_with_negatives_and_short_months
    assert_equal %w[2026-10-31 2026-11-30 2026-12-31 2027-01-31 2027-02-28], dates(rule("the last day of every month").next(5, after: AFTER))
    assert_equal %w[2026-10-31 2026-12-31 2027-01-31 2027-03-31], dates(rule("every 31st").next(4, after: AFTER))
    assert_equal %w[2026-10-19 2026-11-19], dates(rule("19th of every month").next(2, after: AFTER))
  end

  def test_r17_bymonth_and_leap_days
    assert_equal %w[2027-01-01 2028-01-01], dates(rule("every january 1st").next(2, after: AFTER))
    assert_equal %w[2028-02-29 2032-02-29 2036-02-29], dates(rule("every feb 29").next(3, after: AFTER))
  end

  def test_r17_bysetpos
    assert_equal %w[2026-10-30 2026-11-30 2026-12-31 2027-01-29], dates(rule("the last weekday of every month").next(4, after: AFTER))
    assert_equal %w[2026-11-02 2026-12-01 2027-01-01 2027-02-01], dates(rule("the first weekday of every month").next(4, after: AFTER))
  end

  def test_r17_byhour_and_byminute
    out = rule("every day at 8:30 and 17:30").next(3, after: AFTER)
    assert_equal ["2026-10-17 17:30:00 -04:00", "2026-10-18 08:30:00 -04:00", "2026-10-18 17:30:00 -04:00"], walls(out)
    out = rule("every tuesday and thursday at 6pm").next(3, after: AFTER)
    assert_equal ["2026-10-20 18:00:00 -04:00", "2026-10-22 18:00:00 -04:00", "2026-10-27 18:00:00 -04:00"], walls(out)
  end

  def test_r17_frequencies_finer_than_a_day
    assert_equal ["2026-10-17 15:00:00 -04:00", "2026-10-17 16:00:00 -04:00"], walls(rule("every hour").next(2, after: AFTER))
    assert_equal ["2026-10-17 14:01:00 -04:00"], walls(rule("every minute").next(after: AFTER))
  end

  def test_r17_a_part_left_out_comes_from_dtstart
    on31 = { now: "2026-10-31T10:00", zone: "UTC" }
    assert_equal %w[2026-10-31 2026-12-31 2027-01-31], dates(Acute.recurrence("monthly", **on31).next(3, after: Time.utc(2026, 10, 1)))
    assert_equal %w[2026-10-17 2027-10-17], dates(rule("yearly").each.first(2))
    assert_equal %w[2026-10-17 2026-10-24], dates(rule("weekly").each.first(2))
  end

  def test_r17_count_runs_from_dtstart
    r = rule("every other friday 5 times")
    assert_equal %w[2026-10-23 2026-11-06 2026-11-20 2026-12-04 2026-12-18], dates(r.next(10, after: Date.new(2026, 10, 1)))
    assert_equal %w[2026-12-04 2026-12-18], dates(r.next(10, after: Date.new(2026, 11, 20)))
    assert_equal [], r.next(after: Date.new(2026, 12, 18))
    assert_equal 3, rule("every 10 minutes 3 times").next(5, after: Time.utc(2020)).size
  end

  def test_r17_an_excepted_date_still_counts
    r = rule("every monday 5 times except october 26")
    assert_equal %w[2026-10-19 2026-11-02 2026-11-09 2026-11-16], dates(r.each.to_a)
  end

  def test_r17_until_includes_its_end
    assert_equal "2026-10-23 09:00:00 -04:00", wall(rule("every day at 9am until friday").each.to_a.last)
    assert_equal "2026-12-28", rule("every monday until december").each.to_a.last.iso8601
    assert_equal 6, rule("every 10 minutes for an hour").each.count
    assert_equal [], rule("every monday until december").next(after: Date.new(2026, 12, 28))
  end

  def test_r17_exdate
    assert_equal %w[2026-10-26 2026-11-09], dates(rule("every monday except november 2").next(2, after: Date.new(2026, 10, 19)))
    out = rule("every day at 9am except halloween").between(Date.new(2026, 10, 30), Date.new(2026, 11, 1))
    assert_equal ["2026-10-30 09:00:00 -04:00", "2026-11-01 09:00:00 -05:00"], walls(out)
  end

  # R18: clock changes

  def test_r18_the_wall_time_is_kept_across_a_change
    out = rule("every weekday at 9am").between(Date.new(2026, 10, 30), Date.new(2026, 11, 2))
    assert_equal ["2026-10-30 09:00:00 -04:00", "2026-11-02 09:00:00 -05:00"], walls(out)
  end

  def test_r18_new_york_skipped_and_repeated_times
    spring = Date.new(2027, 3, 13)..Date.new(2027, 3, 15)
    r = ->(opts = {}) { rule("every day at 2:30am", **opts).between(spring.begin, spring.end) }
    assert_equal ["2027-03-13 02:30:00 -05:00", "2027-03-14 03:30:00 -04:00", "2027-03-15 02:30:00 -04:00"], walls(r.call)
    assert_equal "2027-03-14 01:30:00 -05:00", wall(r.call(dst: :earlier)[1])
    assert_equal "2027-03-14 03:30:00 -04:00", wall(r.call(dst: :later)[1])
    assert_equal ["2027-03-13 02:30:00 -05:00", "2027-03-15 02:30:00 -04:00"], walls(r.call(dst: :reject))

    fall = ->(opts = {}) { rule("every day at 1:30am", **opts).between(Date.new(2026, 11, 1), Date.new(2026, 11, 1)) }
    assert_equal ["2026-11-01 01:30:00 -04:00"], walls(fall.call)
    assert_equal ["2026-11-01 01:30:00 -05:00"], walls(fall.call(dst: :later))
    assert_equal [], fall.call(dst: :reject)
  end

  def test_r18_a_rejected_time_does_not_count
    r = Acute.recurrence("every day at 1:30am 3 times", now: "2026-10-31T00:00", zone: NY, dst: :reject)
    assert_equal ["2026-10-31 01:30:00 -04:00", "2026-11-02 01:30:00 -05:00", "2026-11-03 01:30:00 -05:00"], walls(r.each.to_a)
  end

  def test_r18_sydney_and_london
    syd = Acute.recurrence("every sunday at 2:30am", now: "2026-09-20T12:00", zone: "Australia/Sydney")
    assert_equal ["2026-09-27 02:30:00 +10:00", "2026-10-04 03:30:00 +11:00", "2026-10-11 02:30:00 +11:00"], walls(syd.next(3, after: Time.utc(2026, 9, 20)))
    lon = Acute.recurrence("every day at 1:30am", now: "2027-03-26T12:00", zone: "Europe/London")
    assert_equal ["2027-03-27 01:30:00 +00:00", "2027-03-28 02:30:00 +01:00", "2027-03-29 01:30:00 +01:00"], walls(lon.next(3, after: Time.utc(2027, 3, 26)))
    lon = Acute.recurrence("every sunday at 1:30am", now: "2026-10-20T12:00", zone: "Europe/London")
    assert_equal "2026-10-25 01:30:00 +01:00", wall(lon.next(after: Time.utc(2026, 10, 20))[0])
  end

  def test_r18_two_times_on_one_instant_are_one_occurrence
    out = rule("every day at 2:30am and 3:30am").between(Date.new(2027, 3, 14), Date.new(2027, 3, 14))
    assert_equal ["2027-03-14 03:30:00 -04:00"], walls(out)
  end

  def test_r18_finer_than_a_day_steps_in_elapsed_time
    r = rule("every 30 minutes")
    out = r.between(Time.utc(2026, 11, 1, 5), Time.utc(2026, 11, 1, 7, 1))
    assert_equal ["2026-11-01 01:00:00 -04:00", "2026-11-01 01:30:00 -04:00", "2026-11-01 01:00:00 -05:00",
                  "2026-11-01 01:30:00 -05:00", "2026-11-01 02:00:00 -05:00"], walls(out)
    out = r.between(Time.utc(2027, 3, 14, 6, 30), Time.utc(2027, 3, 14, 7, 1))
    assert_equal ["2027-03-14 01:30:00 -05:00", "2027-03-14 03:00:00 -04:00"], walls(out)
  end

  # Shapes no phrase makes yet, checked against python-dateutil
  def built(freq, start, interval: 1, month: nil, monthdays: [], days: [], nths: [], secs: [], count: nil, until_: nil)
    parts = Acute::Rule::Parts.new(freq, interval, month, monthdays, days, nths, nil, secs)
    timed = start.size > 3
    start = timed ? Time.utc(*start).to_i : Date.new(*start).jd - 2_440_588
    Acute::Rule.new(parts, NY, start, timed, count, until_, [], false)
  end

  def first(r, n) = r.each.first(n).map { Date === _1 ? _1.iso8601 : _1.strftime("%FT%R") }

  def test_r17_day_filters_on_coarse_frequencies
    assert_equal %w[2026-10-31 2026-11-01 2026-11-30 2026-12-01], first(built(:daily, [2026, 10, 17], monthdays: [1, -1]), 4)
    assert_equal %w[2027-02-01 2027-02-02 2027-02-03], first(built(:daily, [2026, 10, 17], month: 2), 3)
    assert_equal %w[2026-12-07 2026-12-14 2026-12-21 2026-12-28 2027-12-06], first(built(:weekly, [2026, 10, 19], month: 12, days: [1]), 5)
    assert_equal %w[2027-03-10 2028-03-10], first(built(:monthly, [2027, 3, 10], month: 3, monthdays: [10]), 2)
    assert_equal %w[2026-11-13 2027-08-13 2028-10-13 2029-04-13], first(built(:monthly, [2026, 11, 13], monthdays: [13], days: [5]), 4)
  end

  def test_r17_a_yearly_rule_with_no_month_runs_over_the_year
    assert_equal %w[2027-01-04 2027-12-31 2028-01-03 2028-12-29], first(built(:yearly, [2027, 1, 4], nths: [[1, 1], [-1, 5]]), 4)
    assert_equal %w[2026-10-15 2026-11-15 2026-12-15 2027-01-15], first(built(:yearly, [2026, 10, 15], monthdays: [15]), 4)
  end

  def test_r17_finer_than_a_day_with_day_filters
    r = built(:hourly, [2026, 10, 17, 22], interval: 3, days: [6, 0])
    assert_equal %w[2026-10-17T22:00 2026-10-18T01:00 2026-10-18T04:00 2026-10-18T07:00], first(r, 4)
    r = built(:minutely, [2026, 10, 17, 23], interval: 20, days: [6], count: 7)
    assert_equal %w[2026-10-17T23:00 2026-10-17T23:20 2026-10-17T23:40 2026-10-24T00:00 2026-10-24T00:20 2026-10-24T00:40 2026-10-24T01:00], first(r, 9)
    r = built(:minutely, [2026, 10, 17, 22], interval: 45, days: [6], until_: Time.utc(2026, 10, 25, 4).to_i)
    all = first(r, 100)
    assert_equal %w[2026-10-17T22:00 2026-10-17T22:45 2026-10-17T23:30 2026-10-24T00:15], all.first(4)
    assert_equal "2026-10-24T23:30", all.last
    assert_equal ["2026-10-24 00:15:00 -04:00"], walls(r.next(after: Time.new(2026, 10, 18, 0, 0, 0, "-04:00")))
  end

  def test_r17_finer_than_a_day_at_set_times
    r = built(:minutely, [2026, 10, 17, 9], interval: 15, secs: [34_200, 63_000])
    assert_equal %w[2026-10-17T09:30 2026-10-17T17:30 2026-10-18T09:30], first(r, 3)
    r = built(:hourly, [2026, 10, 19, 8], interval: 2, days: [1, 2, 3, 4, 5], secs: [30_600, 34_200], count: 5)
    assert_equal %w[2026-10-19T08:30 2026-10-20T08:30 2026-10-21T08:30 2026-10-22T08:30 2026-10-23T08:30], first(r, 9)
  end

  def test_r16_any_time_like_value_works_as_a_bound
    r = rule("daily")
    t = Struct.new(:to_time).new(Time.utc(2026, 10, 20, 16))
    assert_equal %w[2026-10-20 2026-10-21], dates(r.next(2, after: t))
    assert_raises(ArgumentError) { r.between(1, 2) }
    assert_equal %w[2026-10-18 2026-10-19], dates(r.between!(Date.new(2026, 10, 18), Date.new(2026, 10, 19)))
  end

  # R19: limits

  def test_r19_more_than_1000_occurrences_is_a_failure
    r = rule("every minute until 2200")
    assert_nil r.next(1001)
    assert_equal 1000, r.next(1000, after: AFTER).size
    assert_nil r.between(AFTER, AFTER + 86_400)
    assert_equal 1000, r.between(AFTER, AFTER + 60_000).size
    e = assert_raises(Acute::ParseError) { r.between!(AFTER, AFTER + 86_400) }
    assert_equal :occurrence_limit, e.code
    assert_equal :occurrence_limit, assert_raises(Acute::ParseError) { r.next!(1001) }.code
    assert_equal 3, r.next!(3).size
  end

  def test_r19_the_step_budget_stops_a_long_search
    r = rule("every weekday at 9am 1000000 times")
    t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    assert_nil r.next(after: Time.utc(2600))
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - t, :<, 1
    assert_equal :step_limit, assert_raises(Acute::ParseError) { r.next!(after: Time.utc(2600)) }.code
    assert_equal 1, r.next(after: Time.utc(2100)).size
  end

  def test_r19_a_rule_that_never_occurs_ends_at_the_budget
    parts = Acute::Rule::Parts.new(:yearly, 1, 2, [30], [], [], nil, [])
    r = Acute::Rule.new(parts, "UTC", 20_000, false, nil, nil, [], false)
    assert_nil r.next
    assert_nil r.between(Date.new(2026, 1, 1), Date.new(2400, 1, 1))
    assert_equal [], r.each.first(1)
  end

  def test_occurrences_work_in_a_ractor
    r = rule("every weekday at 9am")
    was = Warning[:experimental]
    Warning[:experimental] = false
    out = ractor_value(Ractor.new(r, AFTER) { |x, a| x.next(2, after: a) })
    Warning[:experimental] = was
    assert_equal ["2026-10-19 09:00:00 -04:00", "2026-10-20 09:00:00 -04:00"], walls(out)
  end

  # Every rule case's first occurrence is its DTSTART
  def test_every_corpus_rule_starts_at_its_dtstart
    cases = Dir[File.expand_path("../cases/*.jsonl", __dir__)].flat_map { |f| File.readlines(f).map { JSON.parse(_1) } }
    cases.select! { _1["expect"]["rrule"] }
    assert_operator cases.size, :>, 150
    cases.each do |c|
      r = Acute.recurrence(c["text"], now: c["now"], zone: c["tz"])
      start = r.dtstart
      assert_equal [start], r.next(after: start - 1), "#{c["id"]} #{c["text"]}"
      assert_equal [start], r.each.first(1), c["id"]
    end
  end
end
