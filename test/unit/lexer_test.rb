require_relative "../test_helper"

class LexerTest < Minitest::Test
  L = Acute::Lexer

  def tokens(s) = L.inspect_tokens(L.lex(s), s)

  def test_clock_meridiem_and_day_words
    assert_equal ['CLOCK(43000, flags=0x1) "4:30"', 'MER(12) "p.m"', 'DAY(1) "tomorrow"'], tokens("4:30 p.m. tomorrow")
  end

  def test_numbers_carry_digit_count_and_leading_zero
    assert_equal ['AT(0) "at"', 'NUM(930, flags=0x14) "0930"'], tokens("at 0930")
    assert_equal ['CLOCK(163015, flags=0x22) "16:30:15"'], tokens("16:30:15")
  end

  def test_case_insensitive_and_at_sign
    assert_equal ['AT(0) "@"', 'NAMED(12) "NOON"', 'DAY(-1) "Yesterday"'], tokens("@NOON, Yesterday")
  end

  def test_unknown_word_is_a_failure_with_byte_range
    assert_equal Acute::Failure.new(:unknown_word, 9, 14), L.lex("tomorrow foo's")
    assert_equal Acute::Failure.new(:unknown_word, 0, 2), L.lex("é")
    assert_equal :unknown_word, L.lex("tomorrowtomorrowtomorrow").code
    assert_equal :unknown_word, L.lex("4pm!?").code
  end

  def test_malformed_clocks
    assert_equal :invalid_date, L.lex("4:3").code
    assert_equal :invalid_date, L.lex("123:00").code
    assert_equal :invalid_date, L.lex("4:30:7").code
  end

  def test_unknown_ranges_finds_every_unknown_word
    assert_equal [0...3, 13...15, 16...19], L.unknown_ranges("foo tomorrow ?? bar")
  end
end
