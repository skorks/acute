require_relative "../test_helper"
require "json"

class RuleTest < Minitest::Test
  cover "Acute::Rule*"
  cover "Acute::Resolve::Recur*"
  OPTS = { now: "2026-10-17T14:00", zone: NY }.freeze

  def rule(text, **opts) = Acute.recurrence(text, **OPTS, **opts)

  def test_r1_a_timed_rule_has_a_zoned_dtstart
    r = rule("every weekday at 9am")
    assert_equal :rule, r.kind
    assert_equal "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR;BYHOUR=9;BYMINUTE=0", r.rrule
    assert_equal "DTSTART;TZID=America/New_York:20261019T090000\nRRULE:#{r.rrule}", r.to_ical
    assert_equal Time.new(2026, 10, 19, 9, 0, 0, "-04:00"), r.dtstart
    assert_equal "-04:00", r.dtstart.strftime("%:z")
  end

  def test_r6_a_weekday_range_is_each_day_of_it
    weekdays = "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"
    assert_equal "#{weekdays};BYHOUR=19;BYMINUTE=20", rule("every Monday through Friday at 19:20").rrule
    assert_equal "#{weekdays};BYHOUR=9;BYMINUTE=0", rule("every monday to friday at 9am").rrule
    assert_equal "#{weekdays};BYHOUR=9;BYMINUTE=0", rule("every mon-fri at 9").rrule
    assert_equal "#{weekdays};BYHOUR=9;BYMINUTE=0", rule("mondays through fridays at 9am").rrule
    assert_equal "FREQ=WEEKLY;BYDAY=MO,FR,SA,SU", rule("every friday through monday").rrule
    assert_equal "FREQ=WEEKLY;BYDAY=MO,WE,TH,FR", rule("every monday and wednesday to friday").rrule
    assert_equal "FREQ=WEEKLY;BYDAY=MO;UNTIL=20261023", rule("every monday until friday").rrule
  end

  def test_r13_a_window_named_without_in_is_read_as_with_it
    november = "DTSTART;VALUE=DATE:20261101\nRRULE:FREQ=DAILY;UNTIL=20261130"
    assert_equal november, rule("every day in november").to_ical
    assert_equal november, rule("every day next month").to_ical
    assert_equal november, rule("everyday next month").to_ical
    assert_equal "DTSTART;VALUE=DATE:20261019\nRRULE:FREQ=WEEKLY;BYDAY=MO,WE;UNTIL=20261024", rule("every monday and wednesday next week").to_ical
    assert_equal "DTSTART;VALUE=DATE:20261017\nRRULE:FREQ=DAILY;UNTIL=20261017", rule("daily this week").to_ical
    assert_nil rule("every day next month in november")
  end

  def test_r1_a_rule_of_whole_days_has_a_date
    r = rule("every monday except november 2")
    assert_equal Date.new(2026, 10, 19), r.dtstart
    assert_equal "DTSTART;VALUE=DATE:20261019\nRRULE:FREQ=WEEKLY;BYDAY=MO\nEXDATE;VALUE=DATE:20261102", r.to_ical
  end

  def test_d30_a_named_hour_after_a_clock_in_its_hour_is_one_time
    r = rule("every day at 12:15 noon")
    assert_equal "FREQ=DAILY;BYHOUR=12;BYMINUTE=15", r.rrule
    assert_equal "every day at 12:15pm", r.to_s
    assert_equal "FREQ=DAILY;BYHOUR=0;BYMINUTE=30", rule("every day at 12:30 midnight").rrule
  end

  def test_r12_an_hourly_rule_leaves_out_every_occurrence_of_an_excepted_date
    [[Date.new(2026, 11, 1), 25], [Date.new(2027, 3, 14), 23]].product(%i[compatible reject]).each do |(day, hours), dst|
      all = rule("every hour", dst: dst).between(day, day)
      assert_equal hours, all.size
      excepted = rule("every hour except #{day.strftime("%B %-d")}", dst: dst)
      assert_equal all.map { _1.strftime("%Y%m%dT%H%M%S") }.uniq.join(","), excepted.to_ical[/EXDATE.*:(.*)/, 1]
      assert_empty excepted.between(day, day)
      assert_equal 24, excepted.between(day + 1, day + 1).size
    end
  end

  def test_r12_an_excepted_time_is_that_instant
    r = rule("every hour except october 17 at 4pm")
    assert_equal [15, 17], r.between(Time.new(2026, 10, 17, 15, 0, 0, "-04:00"), Time.new(2026, 10, 17, 18, 0, 0, "-04:00")).map(&:hour)
    missed = rule("every 2 hours except october 18 at 5pm")
    assert_includes missed.to_ical, "EXDATE;TZID=America/New_York:20261018T170000"
    assert_equal 12, missed.between(Date.new(2026, 10, 18), Date.new(2026, 10, 18)).size
  end

  def test_r12_an_excepted_date_needing_more_than_24_exdates_is_a_conflict
    assert_nil rule("every 15 minutes except october 18")
    e = assert_raises(Acute::ParseError) { Acute.recurrence!("every second except october 18", **OPTS) }
    assert_equal :conflict, e.code
    assert_equal 12, rule("every 2 hours except october 18").to_ical[/EXDATE.*/].count(",") + 1
  end

  def test_r10_until_is_utc_with_a_clock
    assert_equal "FREQ=DAILY;BYHOUR=9;BYMINUTE=0;UNTIL=20261024T035959Z", rule("every day at 9am until friday").rrule
    assert_equal "FREQ=WEEKLY;BYDAY=MO;UNTIL=20261231", rule("every monday until december").rrule
  end

  def test_to_s_is_english_that_reads_back
    { "every weekday at 9am" => "every weekday at 9am",
      "every other friday 5 times" => "every other Friday 5 times",
      "the 2nd and 4th tuesday of every month" => "the second and fourth Tuesday of every month",
      "the last weekday of every month" => "the last weekday of every month",
      "the 1st and 15th of every month" => "the 1st and 15th of every month",
      "every january 1st" => "every year on January 1",
      "every 30 minutes until 5pm" => "every 30 minutes until Oct 17, 2026 5pm",
      "every monday starting november" => "every Monday starting Nov 2, 2026",
      "every 15 minutes from 9 to 5 on weekdays" => "every 15 minutes from 9am to 5pm on weekdays",
      "every 20 minutes between 9pm and midnight" => "every 20 minutes from 9pm to midnight",
      "every day at 9 and 9:30" => "every day at 9am and 9:30am",
      "every weekday except nov 2" => "every weekday except Nov 2, 2026",
      "every day at 9am except nov 2 and nov 3" => "every day at 9am except Nov 2, 2026 and Nov 3, 2026",
      "every hour except oct 18 at 4pm and oct 19" => "every hour except Oct 18, 2026 4pm and Oct 19, 2026",
      "every minute except oct 17 at 4:30pm" => "every minute except Oct 17, 2026 4:30pm" }.each do |text, english|
      r = rule(text)
      assert_equal english, r.to_s, text
      assert_equal r, rule(r.to_s), english
    end
  end

  # R8: ordinals over weekdays say each ordinal and each weekday in the order the BYDAY has them
  def test_r8_ordinals_over_weekdays_read_back
    { "every first monday and friday" => "the first Monday and Friday of every month",
      "every first friday and monday" => "the first Friday and Monday of every month",
      "every 2nd and 4th tuesday" => "the second and fourth Tuesday of every month",
      "the first and last friday of every month" => "the first and last Friday of every month",
      "every first and third monday and friday" => "the first and third Monday and Friday of every month",
      "the second to last and last monday and friday of every month" =>
        "the second to last and last Monday and Friday of every month",
      "the first monday, wednesday and friday of every month" => "the first Monday, Wednesday and Friday of every month",
      "every first monday and friday at 9am 5 times" => "the first Monday and Friday of every month at 9am 5 times" }
      .each do |text, english|
      r = rule(text)
      assert_equal english, r.to_s, text
      assert_equal r.to_ical, rule(r.to_s).to_ical, english
    end
  end

  # R8: a BYDAY no phrase reads, its ordinals not the same for each weekday, says each ordinal with its weekday
  def test_r8_ordinals_differing_by_weekday_say_each_pair
    { [[1, 1], [-1, 5]] => "the first Monday and last Friday of every month",
      [[2, 2], [4, 4]] => "the second Tuesday and fourth Thursday of every month",
      [[1, 1], [3, 1], [1, 5]] => "the first Monday, third Monday and first Friday of every month",
      [[1, 1], [1, 5], [3, 1]] => "the first Monday, first Friday and third Monday of every month" }.each do |nths, english|
      parts = Acute::Rule::Parts.new(:monthly, 1, [], [], [], nths, nil, [])
      r = Acute::Rule.new(parts, NY, Date.new(2026, 11, 2).jd - 2_440_588, false, nil, nil, [], false, now: Time.utc(2026, 10, 17).to_i, text: "built")
      assert_equal english, r.to_s
      assert_nil rule(r.to_s), "the grammar now reads #{english.inspect}: assert it reads back"
    end
  end

  def test_r12_excepted_times_read_back_to_the_same_exdates
    {
      "every hour except october 17 at 4pm" => "every hour except Oct 17, 2026 4pm",
      "every hour except october 17 at 4pm and october 17 at 5pm" => "every hour except Oct 17, 2026 4pm and Oct 17, 2026 5pm",
      "every hour except october 18 at 4pm and october 19 at 5pm" => "every hour except Oct 18, 2026 4pm and Oct 19, 2026 5pm",
      "every hour except october 18" => "every hour except Oct 18, 2026",
      "every hour except november 1" => "every hour except Nov 1, 2026"
    }.each do |text, english|
      r = rule(text)
      assert_equal english, r.to_s, text
      back = rule(r.to_s)
      assert_equal r.to_ical[/EXDATE.*/], back.to_ical[/EXDATE.*/], text
      assert_equal r, back, text
    end
  end

  def test_r9_an_until_before_the_first_occurrence_is_no_rule
    assert_nil rule("every monday until last week")
    assert_nil rule("every day at 9am until 8am")
    error = assert_raises(Acute::ParseError) { Acute.recurrence!("every monday until last week", **OPTS) }
    assert_equal :no_occurrence, error.code
    assert_equal "the rule ends before it starts", error.message
  end

  def test_r15_a_phrase_with_no_rule_word_says_it_is_not_repeating
    error = assert_raises(Acute::ParseError) { Acute.recurrence!("next friday", **OPTS) }
    assert_equal :not_rule, error.code
    assert_equal "not a repeating time", error.message
  end

  def test_r15_a_rule_that_says_how_often_but_not_when_says_so
    ["twice a week", "Twice a month", "3 times a day", "3 times every week", "once or twice a month", "thrice daily",
     "twice a week for 6 weeks", "every morning", "each afternoon", "every evening", "mornings", "every monday morning"].each do |text|
      assert_nil rule(text), text
      e = assert_raises(Acute::ParseError, text) { Acute.recurrence!(text, **OPTS) }
      assert_equal [:vague_rule, "#{text.inspect} says how often, not when", 0...text.size], [e.code, e.message, e.position]
    end
  end

  def test_r15_other_failures_keep_their_codes
    { "this morning" => :not_rule, "3 times" => :not_rule, "next friday" => :not_rule, "every 0 days" => :invalid_date,
      "3 times a day at 9am" => :not_rule, "twice a flurb" => :unknown_word, "every morning flurb" => :unknown_word,
      "twice a week on mondays" => :unknown_word }.each do |text, code|
      assert_equal code, assert_raises(Acute::ParseError, text) { Acute.recurrence!(text, **OPTS) }.code, text
    end
  end

  def test_r5_every_second_is_the_unit_unless_an_ordinal_goes_on
    secondly = "DTSTART;TZID=America/New_York:20261017T140000\nRRULE:FREQ=SECONDLY"
    ["every second", "every Second", "every second,", "every second of the day"].each do |text|
      assert_equal secondly, rule(text).to_ical, text
    end
    assert_equal "FREQ=SECONDLY;UNTIL=20261017T210000Z", rule("every second until 5pm").rrule
    { "every 2nd" => "FREQ=MONTHLY;BYMONTHDAY=2", "every second of the month" => "FREQ=MONTHLY;BYMONTHDAY=2",
      "every second monday" => "FREQ=MONTHLY;BYDAY=2MO", "every second day" => "FREQ=DAILY;INTERVAL=2",
      "every second tuesday of the month" => "FREQ=MONTHLY;BYDAY=2TU", "every second and fourth friday" => "FREQ=MONTHLY;BYDAY=2FR,4FR",
      "every second to last friday" => "FREQ=MONTHLY;BYDAY=-2FR" }.each do |text, rrule|
      assert_equal rrule, rule(text).rrule, text
    end
  end

  def test_describe_gives_the_english
    assert_equal "every day at 8:30am and 5:30pm", Acute.describe(rule("every day at 8:30 and 17:30"))
  end

  def test_to_h_and_json
    r = rule("Every day at 9")
    h = { kind: "rule", text: "Every day at 9", description: "every day at 9am", rrule: "FREQ=DAILY;BYHOUR=9;BYMINUTE=0",
          dtstart: "2026-10-18T09:00:00-04:00", zone: "America/New_York", ical: r.to_ical,
          cron: "0 9 * * *", cron_reason: nil }
    assert_equal h, r.to_h
    assert_equal h.transform_keys(&:to_s), JSON.parse(r.to_json)
    assert_equal h.transform_keys(&:to_s), r.as_json
    assert_equal "2026-10-19", rule("every monday").to_h[:dtstart]
    assert_equal [nil, "cron can't express \"until\""], rule("every monday until june").to_h.values_at(:cron, :cron_reason)
  end

  def test_text_is_the_input_and_to_s_the_wording
    input = +"Every day at 9"
    r = rule(input)
    assert_equal ["Every day at 9", "every day at 9am"], [r.text, r.to_s]
    refute_predicate input, :frozen?
    x = Acute.extract("standup every weekday at 9:30 sharp", **OPTS)
    assert_equal "every weekday at 9:30", x.mentions[0].value.text
    assert_equal "*/15 9-17 * * 1-5", Acute::Rule.from_cron("*/15 9-17 * * 1-5", **OPTS).text
    assert_equal "every day at 9", Acute.read("every day at 9", **OPTS).text
  end

  def test_frozen_and_shareable
    r = rule("every day at 9am")
    assert_predicate r, :frozen?
    assert Ractor.shareable?(r)
  end

  def test_equality_and_inspect
    assert_equal rule("every monday"), rule("mondays")
    refute_equal rule("every monday"), rule("every tuesday")
    assert_equal rule("every monday").hash, rule("on mondays").hash
    assert_equal "#<Acute::Rule DTSTART;VALUE=DATE:20261019 RRULE:FREQ=WEEKLY;BYDAY=MO>", rule("every monday").inspect
  end

  # Two phrasings of one rule are equal; rules with the same iCal that list, describe or count from differently aren't
  def test_equality_covers_what_the_ical_leaves_out
    assert_equal rule("every monday starting jan 4 2027"), rule("mondays starting january 4th 2027")
    assert_equal rule("every day at 2:30am"), rule("every day at 2:30am", dst: :compatible)
    spring = Date.new(2027, 3, 14)
    [[rule("every day at 2:30am", dst: :earlier), rule("every day at 2:30am", dst: :reject), -> { _1.between(spring, spring) }],
     [rule("every monday starting jan 4 2027"), rule("every monday", now: "2027-01-04T00:00"), :to_s.to_proc],
     [rule("every monday", now: Time.utc(2026, 10, 17, 20)), rule("every monday", now: Time.utc(2026, 10, 17, 20), zone: "Asia/Tokyo"),
      -> { _1.next(after: Time.utc(2026, 10, 19, 16)) }]].each do |a, b, differs|
      assert_equal a.to_ical, b.to_ical
      refute_equal differs.(a), differs.(b), a.text
      refute_equal a, b, a.text
      refute a.eql?(b)
      refute_equal a.hash, b.hash
    end
  end

  def test_now_is_not_part_of_equality
    a = rule("every monday at 9am", now: "2026-10-17T14:00")
    b = rule("every monday at 9am", now: "2026-10-17T14:00:01")
    assert_equal a, b
    assert_equal a.hash, b.hash
    assert_equal 1, [a, b].uniq.size
    assert_equal Acute.recurrence("every monday at 9am"), Acute.recurrence("every monday at 9am")
  end

  def test_r15_not_rules_are_nil
    ["next friday", "this weekend", "3 days", "twice a week", "3 times a day", "every morning", "every 0 days",
     "every feb 30", "every day at 9am and 5:30pm", "", "every"].each do |text|
      assert_nil rule(text), text
    end
  end

  def test_recurrence_bang_raises_what_recurrence_returns_nil_for
    assert_equal rule("weekly"), Acute.recurrence!("weekly", **OPTS)
    e = assert_raises(Acute::ParseError) { Acute.recurrence!("next friday", **OPTS) }
    assert_equal :not_rule, e.code
    assert_raises(Acute::ParseError) { Acute.recurrence!("every feb 30", **OPTS) }
    assert_raises(Acute::ParseError) { Acute.recurrence!("x" * 600, **OPTS) }
    assert_raises(Acute::ParseError) { Acute.recurrence!("\xff".b.force_encoding("UTF-8"), **OPTS) }
    assert_raises(ArgumentError) { Acute.recurrence(3) }
  end

  def test_parser_passes_its_options
    p = Acute.with(**OPTS)
    assert_equal rule("every monday at 9am"), p.recurrence("every monday at 9am")
    assert_equal rule("daily"), p.recurrence!("daily")
  end
end
