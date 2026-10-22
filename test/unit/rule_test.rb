require_relative "../test_helper"
require "json"

class RuleTest < Minitest::Test
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

  def test_r1_a_rule_of_whole_days_has_a_date
    r = rule("every monday except november 2")
    assert_equal Date.new(2026, 10, 19), r.dtstart
    assert_equal "DTSTART;VALUE=DATE:20261019\nRRULE:FREQ=WEEKLY;BYDAY=MO\nEXDATE;VALUE=DATE:20261102", r.to_ical
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
      "every day at 9am except nov 2 and nov 3" => "every day at 9am except Nov 2, 2026 and Nov 3, 2026" }.each do |text, english|
      r = rule(text)
      assert_equal english, r.to_s, text
      assert_equal r, rule(r.to_s), english
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

  def test_describe_gives_the_english
    assert_equal "every day at 8:30am and 5:30pm", Acute.describe(rule("every day at 8:30 and 17:30"))
  end

  def test_to_h_and_json
    r = rule("every day at 9am")
    h = { kind: "rule", text: "every day at 9am", rrule: "FREQ=DAILY;BYHOUR=9;BYMINUTE=0",
          dtstart: "2026-10-18T09:00:00-04:00", zone: "America/New_York", ical: r.to_ical,
          cron: "0 9 * * *", cron_reason: nil }
    assert_equal h, r.to_h
    assert_equal h.transform_keys(&:to_s), JSON.parse(r.to_json)
    assert_equal h.transform_keys(&:to_s), r.as_json
    assert_equal "2026-10-19", rule("every monday").to_h[:dtstart]
    assert_equal [nil, "cron can't express \"until\""], rule("every monday until june").to_h.values_at(:cron, :cron_reason)
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
