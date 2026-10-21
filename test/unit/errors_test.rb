require_relative "../test_helper"

class ErrorsTest < Minitest::Test
  def error(text) = assert_raises(Acute::ParseError) { parse(text) }

  def test_parse_returns_nil_where_parse_bang_raises
    assert_nil Acute.parse("blah", zone: "UTC")
    assert_nil Acute.parse("x" * 513, zone: "UTC")
    assert_kind_of Acute::Error, error("blah")
    assert_kind_of StandardError, error("blah")
  end

  def test_d18_an_offset_of_a_day_or_more_fails_rather_than_raising_inside
    ["3pm +99:99", "3pm +24:00", "3pm +2400", "3pm +05:75"].each do |text|
      assert_nil Acute.parse(text, zone: "UTC"), text
      assert_equal :conflict, error(text).code, text
    end
    e = error("3pm JST+23:00")
    assert_equal :invalid_date, e.code
    assert_equal '"23:00" is not a valid time', e.message
    assert_equal 2026, Acute.parse("3pm GMT-23:59", now: "2026-10-17T14:00", zone: "UTC").time.year
  end

  def test_unknown_word_with_position_and_hint
    e = error("tomorow at 5")
    assert_equal :unknown_word, e.code
    assert_equal 0...7, e.position
    assert_equal ["tomorow"], e.unknown
    assert_equal 'did you mean "tomorrow"?', e.hint
    assert_equal 'unknown word "tomorow"', e.message
  end

  def test_positions_are_in_characters
    e = error("tomorrow café")
    assert_equal 9...13, e.position
    assert_equal ["café"], e.unknown
    assert_nil e.hint
  end

  def test_every_unknown_word_is_listed
    e = error("foo tomorrow bar")
    assert_equal 'unknown words "foo", "bar"', e.message
    assert_equal %w[foo bar], e.unknown
    assert_equal 0...3, e.position
  end

  def test_invalid_times
    assert_equal :invalid_date, error("13pm").code
    e = error("25:00")
    assert_equal [:invalid_date, "there is no hour 25", 0...5], [e.code, e.message, e.position]
    assert_equal :invalid_date, error("4:61").code
  end

  def test_d48_an_invalid_date_says_what_is_out_of_range
    e = error("june 31")
    assert_equal [:invalid_date, "June has 30 days", 0...7], [e.code, e.message, e.position]
    assert_equal "June has 30 days", error("2026-06-31").message
    assert_equal "April has 30 days", error("the 31st of april").message
    assert_equal "2027 is not a leap year", error("feb 29 2027").message
    assert_equal "2027 is not a leap year", error("leap day 2027").message
    assert_equal "February 2028 has 29 days", error("feb 30 2028").message
    assert_equal "February has 28 days, 29 in a leap year", error("february 30").message
    assert_equal "there is no minute 61", error("10:61").message
    assert_equal "there is no second 61", error("10:30:61").message
    assert_equal "there is no hour 13 on a 12-hour clock", error("13pm").message
    assert_equal '"4:3" is not a valid time', error("4:3").message
  end

  def test_incomplete_and_conflicting_phrases
    assert_equal :incomplete, error("").code
    assert_equal :incomplete, error("tomorrow at").code
    assert_equal :incomplete, error("in 3").code
    assert_equal :incomplete, error("22/0y4").code # a fraction over zero is no count of units
    e = error("4pm 5")
    assert_equal [:conflict, 4...5], [e.code, e.position]
    assert_equal :conflict, error("today tomorrow").code
  end

  def test_too_long_counts_characters
    assert_equal :too_long, error("x" * 513).code
    assert_equal :unknown_word, error("é" * 300).code
  end

  def test_bad_arguments_raise_argument_error
    assert_raises(ArgumentError) { Acute.parse(nil) }
    assert_raises(ArgumentError) { Acute.parse("4pm", zone: "Mars/Olympus") }
    assert_raises(ArgumentError) { Acute.parse("4pm", now: "next week") }
    assert_raises(ArgumentError) { Acute.parse("4pm", now: "2026-02-30") }
    assert_raises(ArgumentError) { Acute.parse("4pm", now: 5) }
    assert_raises(ArgumentError) { Acute.parse("4pm", context: :sideways) }
  end

  def test_a_bad_option_raises_an_option_error_naming_it
    e = assert_raises(Acute::OptionError) { Acute.parse("4pm", zone: "Mars/Olympus") }
    assert_equal [:zone, "Mars/Olympus"], [e.option, e.value]
    assert_kind_of ArgumentError, e
    assert_kind_of Acute::Error, e
    refute_kind_of Acute::ParseError, e
    assert_equal :context, assert_raises(Acute::OptionError) { Acute.parse("4pm", context: :sideways) }.option
  end

  def test_text_that_is_not_a_string_is_a_plain_argument_error
    e = assert_raises(ArgumentError) { Acute.parse(nil) }
    refute_kind_of Acute::OptionError, e
  end
end
