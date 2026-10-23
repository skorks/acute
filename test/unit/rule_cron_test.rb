require_relative "../test_helper"
require "json"

class RuleCronTest < Minitest::Test
  cover "Acute::Rule*"
  OPTS = { now: "2026-10-17T14:00", zone: NY }.freeze

  def rule(text, **opts) = Acute.recurrence(text, **OPTS, **opts)

  def from(line, **opts) = Acute::Rule.from_cron(line, **OPTS, **opts)

  def from!(line, **opts) = Acute::Rule.from_cron!(line, **OPTS, **opts)

  def assert_cron(line, text, **opts)
    r = rule(text, **opts)
    assert_equal line, r.cron, text
    assert_nil r.cron_reason, text
  end

  def assert_no_cron(reason, text, **opts)
    r = rule(text, **opts)
    assert_nil r.cron, text
    assert_equal reason, r.cron_reason, text
  end

  def test_r20_a_standard_five_field_line
    assert_cron "0 9 * * 1-5", "every weekday at 9am"
    assert_cron "30 8,17 * * *", "every day at 8:30 and 17:30"
    assert_cron "0 18 * * 2,4", "every tuesday and thursday at 6pm"
    assert_cron "30 17 * * 4", "thursdays at 17:30"
    assert_cron "0 12 15 * *", "on the 15th of every month at noon"
    assert_cron "0 0 1,15 * *", "the 1st and 15th of every month"
  end

  def test_r20_weekdays_are_listed_not_stepped
    assert_cron "0 0 * * 0,6", "weekends"
    assert_cron "0 0 * * 1,3,5", "mondays, wednesdays and fridays"
  end

  def test_r20_the_line_is_wall_time_in_the_rules_zone
    assert_cron "0 9 * * *", "every day at 9am", zone: "Australia/Sydney"
    r = from("0 9 * * *", zone: "Australia/Sydney")
    assert_equal "DTSTART;TZID=Australia/Sydney:20261018T090000\nRRULE:FREQ=DAILY;BYHOUR=9;BYMINUTE=0", r.to_ical
  end

  def test_r21_cron_has_no_start_end_or_exceptions
    assert_no_cron 'cron can\'t express "until"', "every 2nd thursday until june"
    assert_no_cron 'cron can\'t express "until"', "every day at 9am until friday"
    assert_no_cron 'cron can\'t express "until"', "every monday for 6 weeks"
    assert_no_cron 'cron can\'t express "8 times"', "every tuesday at 6pm 8 times"
    assert_no_cron 'cron can\'t express "starting"', "every monday starting november"
    assert_no_cron 'cron can\'t express "starting"', "every 15 minutes starting at 9:05am"
    assert_no_cron 'cron can\'t express "except"', "every day at 9am except halloween"
    assert_cron "0 0 * * 1-4", "every weekday except fridays" # a weekday left out is not an exception
  end

  def test_r22_whole_days_run_at_midnight
    assert_cron "0 0 * * 1", "every monday"
    assert_cron "0 0 * * *", "every day"
    assert_cron "0 0 29 2 *", "every feb 29"
    assert_cron "0 0 31 * *", "every 31st"
  end

  def test_r22_what_the_rule_leaves_to_dtstart_comes_from_it
    assert_cron "0 0 * * 6", "weekly" # said on Saturday 17 October
    assert_cron "0 0 17 * *", "monthly"
    assert_cron "0 0 17 10 *", "annually"
    assert_cron "0 9 * * *", "every hour at 9am"
  end

  def test_r22_cron_has_no_seconds
    assert_no_cron "cron has no seconds", "every day at 9:30:15"
    assert_no_cron 'cron can\'t express "every 30 seconds"', "every 30 seconds"
  end

  def test_r23_steps_finer_than_a_day_are_on_crons_grid
    assert_cron "*/15 * * * *", "every 15 minutes", now: "2026-10-17T14:07:31"
    assert_cron "* * * * *", "every minute"
    assert_cron "*/30 * * * *", "every 30 minutes"
    assert_cron "0 * * * *", "hourly"
    assert_cron "0 */2 * * *", "every two hours", now: "2026-10-17T15:07"
    assert_cron "0 */2 * * *", "every 120 minutes"
    assert_cron "0 */6 * * *", "every 6 hours"
  end

  def test_r23_a_step_of_months_keeps_dtstarts_months
    assert_cron "0 0 17 */3 *", "quarterly", now: "2026-01-17T14:00"
    assert_cron "0 0 17 */3 *", "every 3 months", now: "2026-04-17T10:00"
    assert_cron "0 0 7 2-12/3 *", "quarterly", now: "2016-11-07T10:00"
    assert_cron "0 0 17 4,10 *", "every 6 months"
    assert_cron "0 0 3 2-12/2 *", "every other month on the 3rd", now: "2026-10-02T10:00"
    assert_cron "0 0 3 */2 *", "every other month on the 3rd", now: "2026-10-04T10:00"
    assert_equal "FREQ=MONTHLY;INTERVAL=6;BYMONTHDAY=1;BYHOUR=9;BYMINUTE=0", from("0 9 1 1,7 *").rrule
  end

  def test_r23_an_interval_that_doesnt_divide_its_field_has_no_cron
    assert_no_cron 'cron can\'t express "every 40 minutes"', "every 40 minutes" # whenever#548
    assert_no_cron 'cron can\'t express "every 90 minutes"', "every 90 minutes"
    assert_no_cron 'cron can\'t express "every 5 hours"', "every 5 hours"
    assert_no_cron 'cron can\'t express "every other day"', "every other day"
    assert_no_cron 'cron can\'t express "every other week"', "every other week"
    assert_no_cron 'cron can\'t express "every other"', "every other tuesday"
    assert_no_cron 'cron can\'t express "every 3 weeks"', "every three weeks"
    assert_no_cron 'cron can\'t express "every 5 months"', "every 5 months"
    assert_no_cron 'cron can\'t express "every other year"', "every 2 years"
  end

  def test_r24_no_ordinal_weekdays_or_counting_from_the_end
    assert_no_cron 'cron can\'t express "the second Tuesday"', "every second tuesday"
    assert_no_cron 'cron can\'t express "the second and fourth Tuesday"', "the 2nd and 4th tuesday of every month"
    assert_no_cron 'cron can\'t express "the last Friday"', "the last friday of every month"
    assert_no_cron 'cron can\'t express "the last weekday"', "the last weekday of every month"
    assert_no_cron 'cron can\'t express "the last day"', "the last day of every month"
  end

  def test_r25_from_cron_reads_a_line_as_a_rule
    assert_equal "every Friday at 6:30pm", from("30 18 * * 5").to_s
    assert_equal "every weekday at 9am", from("0 9 * * 1-5").to_s
    r = from("0 9 * * 1-5")
    assert_equal "DTSTART;TZID=America/New_York:20261019T090000\nRRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR;BYHOUR=9;BYMINUTE=0", r.to_ical
    assert_equal "FREQ=MONTHLY;BYMONTHDAY=1,15;BYHOUR=0,12;BYMINUTE=30", from("30 0,12 1,15 * *").rrule
    assert_equal "FREQ=YEARLY;BYMONTH=7;BYMONTHDAY=4;BYHOUR=12;BYMINUTE=0", from("0 12 4 7 *").rrule
    assert_equal "FREQ=MINUTELY;INTERVAL=15", from("*/15 * * * *").rrule
    assert_equal "FREQ=DAILY;BYHOUR=0,5,10,15,20;BYMINUTE=0", from("0 */5 * * *").rrule # cron's */5 restarts at midnight
    assert_equal "FREQ=HOURLY;INTERVAL=2", from("0 */2 * * *").rrule
    assert_equal "FREQ=DAILY;BYHOUR=1,3,5,7,9,11,13,15,17,19,21,23;BYMINUTE=0", from("0 1-23/2 * * *").rrule
    assert_equal "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR;BYHOUR=9,10,11,12,13,14,15,16,17;BYMINUTE=0", from("0 9-17 * * 1-5").rrule
  end

  def test_r25_names_sunday_seven_and_macros
    assert_equal from("0 9 * * 1-5"), from("0 9 * * MON-fri")
    assert_equal from("0 9 1 1 *"), from("0 9 1 jan *")
    assert_equal from("0 9 * * 0"), from("0 9 * * 7")
    assert_equal from("0 9 * * 0,6"), from("0 9 * * 6-7")
    { "@yearly" => "0 0 1 1 *", "@annually" => "0 0 1 1 *", "@monthly" => "0 0 1 * *", "@weekly" => "0 0 * * 0",
      "@daily" => "0 0 * * *", "@midnight" => "0 0 * * *", "@hourly" => "0 * * * *" }.each do |macro, line|
      assert_equal from(line), from(macro), macro
      assert_equal line, from(macro).cron, macro
    end
    assert_equal from("0 9 * * *"), from("  0\t9  * * *\n")
  end

  def test_r25_dtstart_is_the_first_run_on_or_after_now
    assert_equal Time.new(2026, 10, 17, 14, 15, 0, "-04:00"), from("*/15 * * * *", now: "2026-10-17T14:07:31").dtstart
    assert_equal Time.new(2026, 10, 17, 14, 0, 0, "-04:00"), from("*/15 * * * *").dtstart # now itself counts
    assert_equal Time.new(2026, 10, 17, 16, 0, 0, "-04:00"), from("0 */2 * * *", now: "2026-10-17T15:07").dtstart
    assert_equal Time.new(2028, 2, 29, 0, 0, 0, "-05:00"), from("0 0 29 2 *").dtstart
    # a step of months starts in one of its months, so the rule's months are cron's
    r = from("0 0 31 */2 *")
    assert_equal Time.new(2027, 1, 31, 0, 0, 0, "-05:00"), r.dtstart
    assert_equal "0 0 31 */2 *", r.cron
    assert_equal "0 0 17 2-12/3 *", from("0 0 17 2-12/3 *").cron
  end

  def test_r25_dtstart_agrees_with_cron_counting_minute_by_minute
    now = Time.utc(2026, 10, 17, 14, 7)
    ["0 9 * * 1-5", "30 0,12 1,15 * *", "*/20 * * * *", "0 */3 * * *", "15 4 29 2 *", "0 0 31 */2 *", "45 23 * * 0",
     "0 6 13 * *", "1 2 3 4 *", "0 0 1 2-12/3 *", "0 9 1-31 * 1", "0 14 * * 6", "7 14 * * *", "*/15 9-17 * * 1-5",
     "0,30 9 * * *", "5-59/15 * * * *", "*/7 * * * *", "10,40 */6 1,15 * *", "0 9 * 11,12 *", "0 9 1,15 11 *",
     "30 8 * 12 1-5"].each do |line|
      assert_equal first_run(line, now), Acute::Rule.from_cron(line, now: now, zone: "UTC").dtstart, line
    end
  end

  def test_r25_several_minutes_are_a_byminute_list
    r = from("*/15 9-17 * * 1-5")
    assert_equal "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR;BYHOUR=9,10,11,12,13,14,15,16,17;BYMINUTE=0,15,30,45", r.rrule
    assert_equal "*/15 9-17 * * 1-5", r.cron
    assert_equal "FREQ=DAILY;BYHOUR=9;BYMINUTE=0,30", from("0,30 9 * * *").rrule
    assert_equal "FREQ=DAILY;BYHOUR=#{(0..23).to_a.join(",")};BYMINUTE=5,20,35,50", from("5-59/15 * * * *").rrule
    assert_equal "FREQ=MONTHLY;BYMONTHDAY=1,15;BYHOUR=0,6,12,18;BYMINUTE=10,40", from("10,40 */6 1,15 * *").rrule
    ["*/15 9-17 * * 1-5", "5-59/15 * * * *", "*/7 * * * *", "10,40 */6 1,15 * *", "*/20 9-11 * * 6"].each do |line|
      assert_equal line, from(line).cron, line
    end
    assert_equal "*/30 9 * * *", from("0,30 9 * * *").cron # R20: the shortest way
  end

  # R27: to_s reads back where the minutes step evenly through the day's window. Where they don't, as */7
  # restarting each hour, it lists every time, which the grammar reads back too
  def test_r27_minute_lists_read_back_from_to_s
    { "*/15 9-17 * * 1-5" => "every 15 minutes from 9am to 6pm on weekdays",
      "5-59/15 * * * *" => "every 15 minutes from 12:05am to midnight",
      "0,20,40 9-11 * * 6" => "every 20 minutes from 9am to 12pm on Saturdays",
      "0,30 9 * * *" => "every day at 9am and 9:30am",
      "10,40 */6 1,15 * *" => "the 1st and 15th of every month at 12:10am, 12:40am, 6:10am, 6:40am, 12:10pm, 12:40pm, 6:10pm and 6:40pm" }.each do |line, english|
      r = from(line)
      assert_equal english, r.to_s, line
      assert_equal r, rule(english), english
    end
    assert_equal from("*/7 9 * * *"), rule(from("*/7 9 * * *").to_s)
    assert_equal "every hour from 9am to 6pm", from("0 9-17 * * *").to_s
    assert_equal from("0 9-17 * * *"), rule("every hour from 9am to 6pm")
  end

  # R4, R27: hours against minutes read as one phrase, not every time listed. A window's end is always the step
  # after the last, so the description reads back.
  def test_r27_hours_against_minutes_read_as_one_phrase
    { "0-10 11 * * *" => "every minute from 11am to 11:11am",
      "0-59 9 * * *" => "every minute from 9am to 10am",
      "5,10 * * * *" => "every hour at :05 and :10",
      "15 * * * 1" => "every hour at :15 on Mondays",
      "5,10 9-17 * * *" => "every hour from 9am to 6pm at :05 and :10",
      "10,40 */2 * * *" => "every 2 hours at :10 and :40",
      "0 */2 * * 1-5" => "every 2 hours on weekdays",
      "0-10 9-17 * * *" => "every minute from :00 to :10 of every hour from 9am to 6pm",
      "0-30/10 * 1 * *" => "the 1st of every month every 10 minutes from :00 to :30 of every hour",
      "0-10 9,11 * * *" => "every minute from :00 to :10 in the 9am and 11am hours",
      "5,10 9,11,15,16,20 * * 6" => "every Saturday at :05 and :10 in the 9am, 11am, 3pm, 4pm and 8pm hours",
      "5,10 * * 3 *" => "every hour at :05 and :10 in March" }.each do |line, english|
      assert_equal english, from(line).to_s, line
    end
  end

  # R28: the minute marks those descriptions say read back to the same times. "in March" is R13's window, so
  # that rule ends where the month does rather than repeating each year, and only its times are compared
  def test_r28_minute_marks_read_back
    ["5,10 * * * *", "5 * * * *", "15 * * * 1", "5,10 9-17 * * *", "10,40 */2 * * *", "0-10 9-17 * * *",
     "0-10 9-17/2 * * *", "0-10 * * * *", "*/7 * * * *", "0-30/10 * 1 * *", "0-10 9,11 * * *",
     "5,10 9,11,15,16,20 * * 6", "5,10 * * * 1-5"].each do |line|
      assert_equal from(line), rule(from(line).to_s), line
    end
    march = from("5,10 * * 3 *")
    assert_equal march.each.first(100), rule(march.to_s).each.first(100)
  end

  def test_r28_minute_marks_need_an_hour_grid
    assert_nil rule("every 5 hours at :05") # n must divide the day
    assert_nil rule("every hour from 9:30am to 5pm at :05")
    assert_nil rule("every day at :05")
    assert_nil rule("every hour at 9am in the 9am hour")
    assert_nil rule("every minute from :10 to :05")
    assert_nil rule("every hour at :05 at :10")
    assert_equal "FREQ=DAILY;BYHOUR=0,3,6,9,12,15,18,21;BYMINUTE=0,15,30", rule("every 15 minutes between :00 and :30 of every 3 hours").rrule
    assert_equal "FREQ=DAILY;INTERVAL=2;BYHOUR=9;BYMINUTE=5", rule("every 2 days at :05 in the 9am hour").rrule
  end

  def test_r28_a_minute_mark_is_its_own_token_and_reads_only_in_a_rule
    assert_equal([[Acute::Lexer::MINUTE, 5]], Acute::Lexer.lex(":05").each_slice(Acute::Lexer::STRIDE).map { _1[0, 2] })
    [":60", "x:05", ":05am", ":5", ":055"].each { refute_equal Acute::Lexer::MINUTE, Acute::Lexer.lex(_1)[0], _1 }
    assert_nil Acute.parse("at :05")
  end

  def test_r27_description_reads_back_to_the_same_rrule
    ["0-10 11 * * *", "0 9-17 * * *"].each do |line|
      r = from(line)
      assert_equal r.to_s, rule(r.to_s).to_s, line
      assert_equal from(line), rule(r.to_s), line
    end
  end

  def test_r25_minute_lists_occur_where_cron_runs
    start = Time.utc(2026, 10, 14)
    stop = start + 3 * 86_400
    ["*/15 9-17 * * 1-5", "0,30 9 * * *", "5-59/15 * * * *", "*/7 * * * *", "10,40 */6 1,15 * *", "5,10 * * 10 *",
     "0-10 11 * 9-11 4-6", "0 9 14,16 10,11 *", "0 9 * */5 *"].each do |line|
      f = line.split
      sets = cron_sets(f)
      want = (start.to_i...stop.to_i).step(60).map { Time.at(_1).utc }.select { match?(_1, sets, f[2].start_with?("*"), f[4].start_with?("*")) }
      assert_equal want, Acute::Rule.from_cron(line, now: start, zone: "UTC").between(start, stop), line
    end
  end

  def test_r25_the_round_trip_holds_for_every_corpus_rule_cron_can_express
    seen = 0
    Dir[File.expand_path("../cases/*.jsonl", __dir__)].each do |file|
      File.foreach(file) do |row|
        c = JSON.parse(row)
        next unless c["expect"]["rrule"]
        r = Acute.recurrence(c["text"], now: c["now"], zone: c["tz"])
        refute_equal r.cron.nil?, r.cron_reason.nil?, c["text"]
        next unless r.cron
        back = Acute::Rule.from_cron!(r.cron, now: c["now"], zone: c["tz"])
        assert_equal r.cron, back.cron, c["text"]
        seen += 1
      end
    end
    assert_operator seen, :>, 80
  end

  # R25: a month field is BYMONTH, read as the other fields are: numbers, names, lists, ranges and steps
  def test_r25_a_month_field_is_bymonth
    { "0 9 * 3 *" => ["FREQ=DAILY;BYMONTH=3;BYHOUR=9;BYMINUTE=0", "every day in March at 9am", "2027-03-01T09:00:00-05:00"],
      "0 9 * mar,jun *" => ["FREQ=DAILY;BYMONTH=3,6;BYHOUR=9;BYMINUTE=0", "every day in March and June at 9am", "2027-03-01T09:00:00-05:00"],
      "0 9 * */4 *" => ["FREQ=DAILY;BYMONTH=1,5,9;BYHOUR=9;BYMINUTE=0", "every day in January, May and September at 9am",
                        "2027-01-01T09:00:00-05:00"],
      "30 8 * 6-8 1-5" => ["FREQ=WEEKLY;BYMONTH=6,7,8;BYDAY=MO,TU,WE,TH,FR;BYHOUR=8;BYMINUTE=30",
                           "every weekday in June, July and August at 8:30am", "2027-06-01T08:30:00-04:00"],
      "0 9 * 7 *" => ["FREQ=DAILY;BYMONTH=7;BYHOUR=9;BYMINUTE=0", "every day in July at 9am", "2027-07-01T09:00:00-04:00"],
      "0 9 1 1,8 *" => ["FREQ=YEARLY;BYMONTH=1,8;BYMONTHDAY=1;BYHOUR=9;BYMINUTE=0", "every year on the 1st of January and August at 9am",
                        "2027-01-01T09:00:00-05:00"],
      "0 9 1,15 7 *" => ["FREQ=YEARLY;BYMONTH=7;BYMONTHDAY=1,15;BYHOUR=9;BYMINUTE=0", "every year on July 1 and 15 at 9am",
                         "2027-07-01T09:00:00-04:00"],
      "*/30 9-10 * dec *" => ["FREQ=DAILY;BYMONTH=12;BYHOUR=9,10;BYMINUTE=0,30", "every 30 minutes from 9am to 11am in December",
                              "2026-12-01T09:00:00-05:00"] }.each do |line, (rrule, english, start)|
      r = from(line)
      assert_equal rrule, r.rrule, line
      assert_equal english, r.to_s, line
      assert_equal start, r.dtstart.iso8601, line
    end
    { "0 9 * mar,jun *" => "0 9 * 3,6 *", "0 9 * */4 *" => "0 9 * */4 *", "30 8 * 6-8 1-5" => "30 8 * 6-8 1-5",
      "0 9 1 1,8 *" => "0 9 1 */7 *", "0 9 1,15 7 *" => "0 9 1,15 7 *" }.each do |line, back|
      assert_equal back, from(line).cron, line
    end
  end

  def test_r25_unsupported_lines_say_why
    { "0 9 * * 1#2" => '"1#2" is not standard cron: no L, W, # or ?',
      "0 9 L * *" => '"L" is not standard cron: no L, W, # or ?',
      "0 9 15W * *" => '"15W" is not standard cron: no L, W, # or ?',
      "0 9 ? * 5L" => '"?" is not standard cron: no L, W, # or ?',
      "@reboot" => "@reboot runs at boot, not at a time" }.each do |line, message|
      assert_nil from(line), line
      e = assert_raises(Acute::ParseError, line) { from!(line) }
      assert_equal :unsupported_cron, e.code, line
      assert_equal message, e.message, line
    end
  end

  def test_r26_day_of_month_or_day_of_week
    e = assert_raises(Acute::ParseError) { from!("0 9 1 * 1") }
    assert_equal :unsupported_cron, e.code
    assert_match(/or/, e.message)
    assert_equal "0 9 * * *", from("0 9 1-31 * 1").cron # either: every day
    assert_equal "0 9 * * *", from("0 9 13 * 0-6").cron
    assert_equal "0 9 * * 1", from("0 9 * * 1").cron
    assert_equal "0 9 13 * *", from("0 9 13 * *").cron
    # a field starting with * makes the days both match, which a rule can't hold with each restricted
    assert_equal :unsupported_cron, assert_raises(Acute::ParseError) { from!("0 9 */2 * 1") }.code
    assert_equal :unsupported_cron, assert_raises(Acute::ParseError) { from!("0 9 13 * */2") }.code
    assert_equal "0 9 */2 * *", from("0 9 */2 * *").cron
  end

  def test_invalid_lines_fail_as_values_with_their_place
    { "" => [0...0, "a cron line has 5 fields, this has 0"],
      "* * * *" => [0...7, "a cron line has 5 fields, this has 4"],
      "* * * * * *" => [0...11, "a cron line has 5 fields, this has 6"],
      "0 9 * * 1-5 /usr/bin/backup" => [0...27, "a cron line has 5 fields, this has 6"],
      "60 * * * *" => [0...2, '"60" is not a minute (0-59)'],
      "0 24 * * *" => [2...4, '"24" is not a hour (0-23)'],
      "0 0 0 * *" => [4...5, '"0" is not a day of the month (1-31)'],
      "0 0 1 13 *" => [6...8, '"13" is not a month (1-12)'],
      "0 0 * * 8" => [8...9, '"8" is not a day of the week (0-7)'],
      "0 0 * foo *" => [6...9, '"foo" is not a month (1-12)'],
      "0 0 * * mon-fry" => [8...15, '"fry" is not a day of the week (0-7)'],
      "jan * * * *" => [0...3, '"jan" is not a minute (0-59)'],
      "*/0 * * * *" => [0...3, "a step of 0 doesn't fit the minute"],
      "*/61 * * * *" => [0...4, "a step of 61 doesn't fit the minute"],
      "5/15 * * * *" => [0...4, 'a step needs a range or *: "5/15"'],
      "30-10 * * * *" => [0...5, '"30-10" runs backwards'],
      "1,,2 * * * *" => [0...4, '"" is not a minute'],
      "1- * * * *" => [0...2, '"1-" is not a minute'],
      "-1 * * * *" => [0...2, '"-1" is not a minute'],
      "007 * * * *" => [0...3, '"007" is not a minute (0-59)'],
      "@often" => [0...6, '"@often" is not a cron macro'],
      "  0 0 30 2 *" => [2...12, "the line never runs"] }.each do |line, (position, message)|
      assert_nil from(line), line
      e = assert_raises(Acute::ParseError, line) { from!(line) }
      assert_equal :invalid_cron, e.code, line
      assert_equal message, e.message, line
      assert_equal position, e.position, line
    end
  end

  def test_hostile_lines_fail_fast_as_values
    hostile = ["1" * 100_000, "#{"1," * 255}1 * * * *", "#{"0-59," * 80}x * * * *", "#{"1," * 200}1-",
               "* " * 300, "9" * 512, " * * * * *", "１ * * * *", "* * *\u0000 * *", "\xff * * * *".b,
               "0 9 * * 1".encode("UTF-16LE"), "((((((((((((((((((((((((a+)+)+)+)+)+)+)+)+)+)+)+)+)+)!",
               "#{"a" * 200}! * * * *", "1-#{"9" * 300} * * * *", "*/#{"9" * 300} * * * *"]
    hostile.each do |line|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      assert_nil from(line), line.b[0, 20].inspect
      e = assert_raises(Acute::ParseError, line.b[0, 20].inspect) { from!(line) }
      assert_includes %i[invalid_cron too_long], e.code
      assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 0.5, line.b[0, 20].inspect
    end
    assert_equal :too_long, assert_raises(Acute::ParseError) { from!("1" * 513) }.code
  end

  def test_a_long_valid_line_is_read
    assert_equal "* * * * *", from("#{(0..59).to_a.join(",")} * * * *").cron
    assert_equal "* * * * *", from("#{"*/1," * 100}* * * * *").cron
    assert_equal "* * * * *", from("#{"0-59," * 80}0 * * * *").cron
  end

  def test_not_a_string_raises
    assert_raises(ArgumentError) { from(nil) }
    assert_raises(ArgumentError) { from(5) }
  end

  def test_from_cron_rules_are_frozen_and_shareable
    r = from("0 9 * * 1-5")
    assert_predicate r, :frozen?
    assert Ractor.shareable?(r)
    was = Warning[:experimental]
    Warning[:experimental] = false
    assert_equal "0 9 * * 1-5", ractor_value(Ractor.new(r, &:cron))
    assert_equal "every weekday at 9am", ractor_value(Ractor.new { Acute::Rule.from_cron("0 9 * * mon-fri", zone: "UTC").to_s })
  ensure
    Warning[:experimental] = was
  end

  private

  # The first minute on or after now that cron runs, in UTC, counting as Vixie cron does
  def first_run(line, now)
    f = line.split
    sets = cron_sets(f)
    t = now
    until match?(t, sets, f[2].start_with?("*"), f[4].start_with?("*"))
      t = day?(t, sets, f[2].start_with?("*"), f[4].start_with?("*")) ? t + 60 : Time.utc(t.year, t.month, t.day) + 86_400
    end
    t
  end

  def cron_sets(fields) = [[0, 59], [0, 23], [1, 31], [1, 12], [0, 6]].each_with_index.map { |(lo, hi), i| expand(fields[i], lo, hi) }

  def expand(field, low, high)
    field.split(",").flat_map do |item|
      range, step = item.split("/")
      a, b = range == "*" ? [low, high] : range.split("-").map(&:to_i)
      a.step(b || a, (step || 1).to_i).to_a
    end
  end

  def day?(t, (_, _, dom, mon, dow), dom_star, dow_star)
    either = dom_star || dow_star ? dom.include?(t.day) && dow.include?(t.wday) : dom.include?(t.day) || dow.include?(t.wday)
    mon.include?(t.month) && either
  end

  def match?(t, sets, dom_star, dow_star) = sets[0].include?(t.min) && sets[1].include?(t.hour) && day?(t, sets, dom_star, dow_star)
end
