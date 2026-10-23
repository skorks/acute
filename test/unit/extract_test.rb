require_relative "../test_helper"

class ExtractTest < Minitest::Test
  def extract(text) = Acute.extract(text, now: "2026-10-17T14:00", zone: NY)

  def mentions(text) = extract(text).mentions.map { [_1.kind, _1.text, _1.offset] }

  def test_mentions_with_their_offsets
    x = extract("Dinner with Sam next Tuesday at 7pm, flight back on the 30th")
    assert_equal([[:time, "next Tuesday at 7pm", 16...35], [:time, "the 30th", 52...60]],
                 x.mentions.map { [_1.kind, _1.text, _1.offset] })
    assert_equal(["2026-10-20 19:00:00 -04:00", "2026-10-30 00:00:00 -04:00"], x.mentions.map { wall(_1.value.begin) })
    assert_equal "Dinner with Sam, flight back", x.remainder
  end

  def test_e2_a_duration_takes_its_for
    x = extract("lunch with bob next tue at 1 for 2 hours")
    assert_equal([[:time, "next tue at 1", 15...28], [:duration, "for 2 hours", 29...40]],
                 x.mentions.map { [_1.kind, _1.text, _1.offset] })
    assert_equal({ hours: 2 }, x.mentions[1].value.parts)
    assert_equal "lunch with bob", x.remainder
    assert_equal [[:time, "a week starting tomorrow", 12...36]], mentions("set ooo for a week starting tomorrow")
  end

  def test_no_mention_starts_inside_a_written_number
    assert_equal [], mentions("The ssn is 123-12-1234")
    assert_equal [[:time, "the morning", 27...38]], mentions("My temperature was 37.1 in the morning")
  end

  def test_remainder_drops_the_word_that_introduced_a_mention
    assert_equal "Pay rent", extract("Pay rent tomorrow 9am").remainder
    assert_equal "Call me; dinner.", extract("Call me tomorrow; dinner at 7pm.").remainder
    assert_equal "She leaves", extract("She leaves in August").remainder
  end

  def test_e4_a_leading_in_is_left_out_when_the_rest_reads_the_same
    assert_equal [[:time, "August", 14...20]], mentions("She leaves in August.")
    assert_equal [[:time, "the day before yesterday", 7...31]], mentions("I left the day before yesterday")
    assert_equal [[:time, "the afternoon", 14...27]], mentions("let's meet in the afternoon")
    assert_equal [[:time, "Tuesday morning", 13...28]], mentions("Lets meet on Tuesday morning")
  end

  def test_e4_a_leading_word_that_changes_the_reading_stays
    assert_equal [[:time, "in 3 days", 8...17]], mentions("see you in 3 days")
    assert_equal [[:time, "in 2016", 16...23]], mentions("You can't leave in 2016")
    assert_equal [[:time, "about 3pm", 5...14]], mentions("meet about 3pm")
  end

  def test_e5_an_abbreviation_dot_does_not_end_the_sentence
    assert_equal [[:time, "Oct. 2", 13...19]], mentions("I'll go back Oct. 2")
    assert_equal [[:time, "Dec. 2021", 15...24]], mentions("the year ended Dec. 2021")
    assert_equal [[:time, "Oct. 2 to October 22", 12...32]], mentions("I'll be out Oct. 2 to October 22")
    assert_equal [[:time, "from 1p.m. to 4", 11...26]], mentions("let's meet from 1p.m. to 4")
    assert_equal [[:time, "Oct", 7...10], [:time, "May 3", 12...17]], mentions("I left Oct. May 3 is next")
  end

  def test_e5_a_meridiem_keeps_its_last_dot_and_a_decade_its_apostrophe
    assert_equal [[:time, "4 a.m.", 6...12]], mentions("up at 4 a.m. again")
    assert_equal [[:time, "3 p . m .", 3...12]], mentions("at 3 p . m .")
    assert_equal [[:time, "4 pm", 3...7]], mentions("at 4 pm.")
    assert_equal [[:time, "'40s", 6...10]], mentions("loved '40s music")
  end

  def test_d48_a_mention_across_a_bracket_takes_both_brackets
    assert_equal [[:time, "[5pm] tomorrow", 5...19]], mentions("meet [5pm] tomorrow")
    assert_equal "2026-10-18 17:00:00 -04:00", wall(extract("meet [5pm] tomorrow").mentions[0].value.begin)
    assert_equal [[:time, "lunch [5pm] tomorrow", 0...20]], mentions("lunch [5pm] tomorrow") # as "lunch 5pm tomorrow"
    assert_equal [[:time, "[Sept] 04, 2014", 4...19]], mentions("see [Sept] 04, 2014 here")
    assert_equal [[:time, "5pm", 6...9]], mentions("meet [5pm]")
    assert_equal [[:time, "lunch [5pm]", 0...11]], mentions("lunch [5pm]")
    assert_equal [[:time, "march 3", 0...7]], mentions("march 3 [2]")
    assert_equal "[5pm] tomorrow", extract("lunch [5pm] tomorrow").mentions[0].text[/\[5pm\] tomorrow/]
  end

  def test_d48_curly_and_single_quotes_are_quotes_as_straight_double_ones_are
    assert_equal [[:duration, "for 3 days", 9...19]], mentions("he said \"for 3 days\" then")
    assert_equal [[:duration, "for 3 days", 9...19]], mentions("he said “for 3 days” then")
    assert_equal [[:duration, "3 days", 9...15]], mentions("he said “3 days” then")
    assert_equal [[:duration, "for 3 days", 1...11]], mentions("“for 3 days”")
    assert_equal [[:duration, "for 3 days", 9...19]], mentions("he said ‘for 3 days’ then")
    assert_equal [[:duration, "for 3 days", 9...19]], mentions("he said 'for 3 days' then")
    assert_equal [[:time, "tomorrow", 1...9]], mentions("‘tomorrow’")
  end

  def test_d48_an_apostrophe_is_still_an_apostrophe
    assert_equal [[:time, "tomorrow’s", 4...14]], mentions("see tomorrow’s game")
    assert_equal [[:time, "presidents’ day", 0...15]], mentions("presidents’ day")
    assert_equal [[:time, "presidents' day", 0...15]], mentions("presidents' day")
    assert_equal [[:time, "in ’90s", 5...12]], mentions("back in ’90s")
  end

  def test_e3_lowercase_english_words_are_not_mentions
    assert_equal [], mentions("this may or may not work")
    assert_equal [], mentions("Sat on the mat. May I go?")
    assert_equal [], mentions("Lunch with Sam")
    assert_equal [], mentions("I have 3 cats")
  end

  def test_e3_a_word_with_something_else_to_say_it_is_a_time_is_a_mention
    assert_equal [[:time, "May 3", 0...5]], mentions("May 3 works")
    assert_equal [[:time, "May", 11...14]], mentions("See you in May.")
  end

  def test_d18_each_day_of_a_list_of_weekdays_is_a_mention
    assert_equal [[:time, "mon", 0...3], [:time, "wed", 5...8], [:time, "fri", 13...16]], mentions("mon, wed and fri")
    assert_equal [[:time, "mon", 12...15], [:time, "wed", 20...23]], mentions("we can meet mon and wed")
    assert_equal [[:time, "Mon", 0...3], [:time, "Wed", 5...8]], mentions("Mon, Wed")
    assert_equal(%w[2026-10-19 2026-10-21], extract("mon or wed").mentions.map { _1.value.begin.to_date.to_s })
    assert_equal [], mentions("she will wed on sat")
    assert_equal [], mentions("mon wed")
  end

  def test_offsets_count_characters
    assert_equal [[:time, "tomorrow at 9am", 5...20]], mentions("café tomorrow at 9am")
  end

  def test_nothing_found
    x = extract("25:99 is not a time")
    assert_equal [], x.mentions
    assert_equal "25:99 is not a time", x.remainder
  end

  def test_a_malformed_clock_does_not_hide_the_rest
    assert_equal [[:time, "tomorrow at 5pm", 15...30]], mentions("meet at 4:3 or tomorrow at 5pm")
  end

  def test_the_longest_accepted_prefix_wins
    assert_equal [[:time, "two days ago 00:00:00", 0...21]], mentions("two days ago 00:00:00 pm")
    assert_equal [[:time, "2004-05-05 12:00:00", 0...19], [:duration, "6 months", 20...28]],
                 mentions("2004-05-05 12:00:00 6 months")
  end

  def test_arguments_are_checked_once
    assert_raises(ArgumentError) { Acute.extract("tomorrow", now: "2026-10-17T14:00", zone: "Nowhere/Land") }
  end

  def seconds
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  end

  # Linear means 4x the text costs about 4x the time; quadratic would cost 16x. Absolute limits fail on a slow runner.
  def best_of_three(&) = Array.new(3) { seconds(&) }.min

  def test_long_text_takes_time_in_proportion_to_its_length
    prose = "We met on the 3rd and talked about the plan for next friday at 3pm before lunch. "
    dense = "next friday tomorrow 3pm june 5th "
    [[prose, 150, 1200], [dense, 375, 4500], ["the day after ", 500, 0]].each do |unit, n, count|
      x = nil
      t1 = best_of_three { extract(unit * n) }
      t4 = best_of_three { x = extract(unit * 4 * n) }
      assert_operator t4 / t1, :<, 8, "#{unit[0, 20]}: 4x the text took #{(t4 / t1).round(1)}x as long (#{t1}s, #{t4}s)"
      assert_equal count, x.mentions.size
    end
    x = nil
    assert_operator seconds { x = extract("5" * 100_000) }, :<, 2
    assert_equal 0, x.mentions.size
  end

  def test_a_mention_is_never_longer_than_a_phrase_parse_takes
    x = extract("#{"the day after " * 40}tomorrow")
    assert_operator x.mentions[0].text.bytesize, :<=, Acute::MAX_LENGTH
  end

  def test_invalid_utf8_is_scrubbed
    x = extract("tomorrow \xFF at 3pm, for 2 hours caf\xC3".dup.force_encoding("UTF-8"))
    assert_equal([[:time, "tomorrow", 0...8], [:time, "3pm", 14...17], [:duration, "for 2 hours", 19...30]],
                 x.mentions.map { [_1.kind, _1.text, _1.offset] })
    assert_predicate x.text, :valid_encoding?
  end

  def test_e2_for_counts_characters_before_it
    assert_equal [[:duration, "for 2 hours", 10...21]], mentions("Réunion é for 2 hours")
  end

  def texts(text) = extract(text).mentions.map(&:text)

  def test_d50_numbers_in_words_alone_are_plain_english
    assert_empty texts("There are two to four people in the room")
    assert_empty texts("One may ask a question")
    assert_equal ["june 28th"], texts("The first free fish is june 28th")
    assert_equal ["the 5th"], texts("see you on the 5th")
    assert_equal ["eight forty"], texts("set an alarm for eight forty")
    assert_equal ["fourth of may"], texts("i'll go back fourth of may")
  end

  def test_d50_an_ordinal_before_times_counts_occasions
    assert_equal ["July 1st"], texts("I'll go back July 1st, 17th times.")
  end

  def test_d50_a_greeting_is_no_mention
    assert_empty texts("Good Morning Paul")
    assert_equal ["this morning"], texts("I saw him this morning")
  end

  def test_d50_nothing_starts_after_a_currency_sign
    assert_equal ["December 27"], texts("I bought it for $12 December 27")
    assert_empty texts("$DEC farming is coming to $CUB Finance!")
  end

  def test_d50_nothing_inside_a_word_or_an_id
    assert_empty texts("see id=~.~3am3ioYcY0KBufXF")
    assert_equal ["3am"], texts("see you at 3am")
  end

  def test_d50_the_same_number_at_both_ends_is_no_range
    assert_empty texts("schedule me a 1-1 meeting")
    assert_equal ["1-3 tomorrow"], texts("free 1-3 tomorrow")
  end

  def test_d50_a_month_abbreviation_before_a_month_is_a_name
    assert_equal ["November 2019"], texts("By Angie Mar November 2019")
  end

  def test_d50_start_and_end_in_lower_case_are_verbs
    assert_equal ["3 minutes from now"], texts("Let's start 3 minutes from now")
    assert_equal ["two months after next Friday"], texts("It will end two months after next Friday.")
    assert_equal ["by end of May"], texts("due by end of May")
  end

  def test_d50_the_leading_word_is_left_out_when_the_rest_reaches_further
    assert_equal ["2 days from today"], texts("I will leave in 2 days from today")
    assert_equal ["12:30 PM ON FRI"], texts("ADD LUNCH AT 12:30 PM ON FRI")
  end

  def test_d50_a_mention_does_not_end_in_a_word_that_introduces
    assert_equal ["May 6th 2004"], texts("on May 6th 2004, the customer returned")
  end

  def test_d50_a_decade_in_words_or_with_an_apostrophe_is_never_seconds
    x = extract("In 70's")
    assert_equal ["70's"], x.mentions.map(&:text)
    assert_equal 10, x.mentions[0].value.end.year - x.mentions[0].value.begin.year
    assert_equal 1990, Acute.parse("in nineties", now: "2026-10-17T14:00", zone: NY).begin.year
    assert_equal 30, Acute.parse("in 30s", now: "2026-10-17T14:00", zone: NY).begin - Time.new(2026, 10, 17, 14, 0, 0, "-04:00")
  end

  def test_d50_this_takes_no_count
    assert_nil Acute.parse("this 5 years", now: "2026-10-17T14:00", zone: NY)
    assert_equal ["5 years ago"], texts("he said this 5 years ago.")
  end

  def test_d51_a_for_that_makes_a_span_belongs_to_the_mention
    m = extract("set OOO for 3 days, from today").mentions
    assert_equal ["for 3 days, from today"], m.map(&:text)
    assert_equal [Time.new(2026, 10, 17, 0, 0, 0, "-04:00"), Time.new(2026, 10, 20, 0, 0, 0, "-04:00")], [m[0].value.begin, m[0].value.end]
    assert_equal ["the past month"], texts("for the past month")
  end

  def test_d51_about_and_within_are_left_out_when_the_rest_reaches_further
    assert_equal ["year 2016 and greater"], texts("How about year 2016 and greater")
    assert_equal ["2 weeks before yesterday"], texts("It will start within 2 weeks before yesterday")
    assert_equal ["about 3pm"], texts("How about 3pm")
  end

  def test_d51_a_bare_number_at_the_end_goes_with_what_follows
    assert_equal ["11/20", "12 of Nov"], texts("Do you know the date? 11/20, 12 of Nov?")
    assert_equal ["3 jan 10"], texts("on 3 jan 10")
  end

  def test_d51_or_later_before_than_is_two
    assert_equal ["between 2015 and 2018", "later than 2020"], texts("sales between 2015 and 2018 or later than 2020")
    assert_nil Acute.parse("2015 or later", now: "2026-10-17T14:00", zone: NY).end
  end

  def test_d51_a_lone_year_joined_to_a_year_mention_is_a_year
    assert_equal ["in 2007", "2009"], texts("Show sales in 2007 and 2009")
    assert_equal ["before 2000", "1998"], texts("sales before 2000 but not 1998")
    assert_equal ["from 2010 – 2020", "2015"], texts("sales from 2010 – 2020 and not 2015")
    assert_empty texts("Show sales of 2007 and 2009")
    assert_equal ["May 3"], texts("May 3 and 12 people")
  end

  def test_d51_a_month_after_in_is_a_month
    assert_equal ["in may"], texts("It may be in may")
    assert_empty texts("It may be fine")
  end

  def test_d51_a_number_after_a_label_is_no_hour
    assert_equal ["this afternoon"], texts("Let's go for coffee on building 4 this afternoon")
    assert_equal ["4 this afternoon"], texts("see you 4 this afternoon")
  end

  def test_d51_a_dotted_version_is_no_date
    assert_equal ["2015-09-24"], texts("1.5.30 - 2015-09-24")
    assert_equal ["23.04.22"], texts("on 23.04.22")
    assert_equal ["2015.5.13"], texts("available on 2015.5.13?")
  end

  def test_d51_parse
    at = ->(t, now, zone = "UTC") { Acute.parse(t, now:, zone:) }
    assert_equal Time.utc(2016, 11, 6, 17), at.("last night", "2016-11-07T00:00:00").begin
    assert_equal Time.utc(2016, 11, 5, 17), at.("last night", "2016-11-07T00:00:01").begin
    assert_equal [Time.utc(2008), Time.utc(2009)], [at.("the year of 2008", "2016-11-07T00:00").begin, at.("the year of 2008", "2016-11-07T00:00").end]
    assert_equal at.("in a fortnight", "2021-05-20T00:00").begin, at.("in a fortnight\u2019s time", "2021-05-20T00:00").begin
  end

  def test_e6_a_rule_is_one_mention
    x = extract("remind me every 2 weeks until June, then call Sam tomorrow")
    assert_equal([[:rule, "every 2 weeks until June", 10...34], [:time, "tomorrow", 50...58]], x.mentions.map { [_1.kind, _1.text, _1.offset] })
    assert_kind_of Acute::Rule, x.mentions[0].value
    assert_equal "rule", x.to_h[:mentions][0][:kind]
    assert_equal "remind me, then call Sam", x.remainder
  end

  def test_e6_a_weekday_range_rule_is_one_mention
    assert_equal([[:rule, "every Monday through Friday at 19:20"]], mentions("standup every Monday through Friday at 19:20").map { _1.take(2) })
    assert_equal([[:rule, "every mon-fri at 9"]], mentions("gym every mon-fri at 9 sharp").map { _1.take(2) })
  end

  def test_e6_a_rule_wins_unless_a_time_reaches_further
    assert_equal([[:rule, "the 1st of every month"]], mentions("pay rent on the 1st of every month").map { _1.take(2) })
    assert_equal([[:rule, "every weekday at 9:30"]], mentions("standup every weekday at 9:30 in room 4").map { _1.take(2) })
  end

  def test_e6_no_rule
    ["hourly rate", "the weekly report", "every second counts", "every time I call"].each do |text|
      assert_empty mentions(text).select { _1[0] == :rule }, text
    end
    assert_equal([[:rule, "every 8 hours"]], mentions("take one every 8 hours").map { _1.take(2) })
  end

  def test_e6_lenient_parse_finds_no_rule
    assert_equal Time.new(2026, 11, 1, 0, 0, 0, "-04:00"), Acute.parse("pay on the 1st of every month", now: "2026-10-17T14:00", zone: NY, strict: false).begin
  end
end
