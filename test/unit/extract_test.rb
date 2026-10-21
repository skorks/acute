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

  def test_long_text_takes_time_in_proportion_to_its_length
    prose = "We met on the 3rd and talked about the plan for next friday at 3pm before lunch. " * 1200
    dense = "next friday tomorrow 3pm june 5th " * 3000
    limit = defined?(Coverage) && Coverage.running? ? 8 : 2 # line coverage slows Ruby severalfold
    [[prose, 2400], [dense, 9000], ["the day after " * 2000, 0], ["5" * 100_000, 0]].each do |text, count|
      x = nil
      assert_operator seconds { x = extract(text) }, :<, limit, text[0, 20]
      assert_equal count, x.mentions.size
    end
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
end
