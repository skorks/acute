require_relative "../test_helper"

class ErrorsTest < Minitest::Test
  def error(text) = assert_raises(Acute::ParseError) { parse(text) }

  def test_parse_returns_nil_where_parse_bang_raises
    assert_nil Acute.parse("blah", zone: "UTC")
    assert_nil Acute.parse("x" * 513, zone: "UTC")
    assert_kind_of Acute::Error, error("blah")
    assert_kind_of StandardError, error("blah")
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
    assert_equal [:invalid_date, '"25:00" is not a valid time', 0...5], [e.code, e.message, e.position]
    assert_equal :invalid_date, error("4:61").code
  end

  def test_incomplete_and_conflicting_phrases
    assert_equal :incomplete, error("").code
    assert_equal :incomplete, error("tomorrow at").code
    assert_equal :incomplete, error("in 3").code
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
end
