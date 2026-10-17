require_relative "../test_helper"

class ExtractTest < Minitest::Test
  def extract(text) = Acute.extract(text, now: "2026-10-17T14:00", zone: NY)

  def mentions(text) = extract(text).mentions.map { [_1.kind, _1.text, _1.offset] }

  def test_mentions_with_their_offsets
    x = extract("Dinner with Sam next Tuesday at 7pm, flight back on the 30th")
    assert_equal [[:time, "next Tuesday at 7pm", 16...35], [:time, "the 30th", 52...60]],
                 x.mentions.map { [_1.kind, _1.text, _1.offset] }
    assert_equal ["2026-10-20 19:00:00 -04:00", "2026-10-30 00:00:00 -04:00"], x.mentions.map { wall(_1.value.begin) }
    assert_equal "Dinner with Sam, flight back", x.remainder
  end

  def test_e2_a_duration_takes_its_for
    x = extract("lunch with bob next tue at 1 for 2 hours")
    assert_equal [[:time, "next tue at 1", 15...28], [:duration, "for 2 hours", 29...40]],
                 x.mentions.map { [_1.kind, _1.text, _1.offset] }
    assert_equal({ hours: 2 }, x.mentions[1].value.parts)
    assert_equal "lunch with bob", x.remainder
  end

  def test_remainder_drops_the_word_that_introduced_a_mention
    assert_equal "Pay rent", extract("Pay rent tomorrow 9am").remainder
    assert_equal "Call me; dinner.", extract("Call me tomorrow; dinner at 7pm.").remainder
  end

  def test_e3_lowercase_english_words_are_not_mentions
    assert_equal [], mentions("this may or may not work")
    assert_equal [], mentions("Sat on the mat. May I go?")
    assert_equal [], mentions("Lunch with Sam")
    assert_equal [], mentions("I have 3 cats")
  end

  def test_e3_a_word_with_something_else_to_say_it_is_a_time_is_a_mention
    assert_equal [[:time, "May 3", 0...5]], mentions("May 3 works")
    assert_equal [[:time, "in May", 8...14]], mentions("See you in May.")
  end

  def test_offsets_count_characters
    assert_equal [[:time, "tomorrow at 9am", 5...20]], mentions("café tomorrow at 9am")
  end

  def test_nothing_found
    x = extract("25:99 is not a time")
    assert_equal [], x.mentions
    assert_equal "25:99 is not a time", x.remainder
  end

  def test_arguments_are_checked_once
    assert_raises(ArgumentError) { Acute.extract("tomorrow", now: "2026-10-17T14:00", zone: "Nowhere/Land") }
  end
end
