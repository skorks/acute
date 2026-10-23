require_relative "../test_helper"

class LexerTest < Minitest::Test
  cover "Acute::Lexer*"
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
    assert_equal ['AT(0) "@"', 'NAMED(12, flags=0x100) "NOON"', 'DAY(-1, flags=0x100) "Yesterday"'], tokens("@NOON, Yesterday")
  end

  def test_clock_in_brackets_loses_them_and_a_footnote_keeps_them
    assert_equal ['CLOCK(53000, flags=0x1) "5:30"', 'MER(12) "pm"'], tokens("[5:30 pm]")
    assert_equal ['CLOCK(170000, flags=0x2) "17:00"'], tokens("[17:00]")
    assert_equal Acute::Failure.new(:unknown_word, 8, 9), L.lex("march 3 [2]")
    assert_equal Acute::Failure.new(:unknown_word, 0, 1), L.lex("[5pm")
    u = []
    L.lex("[5 pm tomorrow] x [1", u)
    assert_equal [0, 1, 14, 15, 16, 17, 18, 19], u
  end

  def test_unknown_word_is_a_failure_with_byte_range
    assert_equal Acute::Failure.new(:unknown_word, 9, 14), L.lex("tomorrow foo's")
    assert_equal Acute::Failure.new(:unknown_word, 0, 2), L.lex("é")
    assert_equal :unknown_word, L.lex("tomorrowtomorrowtomorrow").code
    assert_equal :unknown_word, L.lex("4pm!? friday").code
  end

  def test_malformed_clocks
    assert_equal :invalid_date, L.lex("4:3").code
    assert_equal :invalid_date, L.lex("123:00").code
    assert_equal :invalid_date, L.lex("4:30:7").code
  end

  def test_unknown_ranges_finds_every_unknown_word
    assert_equal [0...3, 13...15, 16...19], L.unknown_ranges("foo tomorrow ?? bar")
  end

  def test_leniently_a_malformed_clock_is_one_unknown_word
    assert_equal [3...7, 17...24], L.unknown_ranges("at 4:3p tomorrow 123:00x")
    assert_equal ['AT(0) "at"', 'DAY(1) "tomorrow"'], L.inspect_tokens(L.lex("at 4:3 tomorrow", []), "at 4:3 tomorrow")
  end

  def test_iso_dates_and_ordinals
    assert_equal ['NUM(2026, flags=0x4) "2026"', 'DASH(0) "-"', 'NUM(10, flags=0x2) "10"', 'DASH(0) "-"', 'NUM(3, flags=0x12) "03"'],
                 tokens("2026-10-03")
    assert_equal ['NUM(2026, flags=0x4) "2026"', 'DASH(0) "-"', 'NUM(1, flags=0x1) "1"', 'DASH(0) "-"', 'NUM(2, flags=0x1) "2"'],
                 tokens("2026-1-2")
    assert_equal ['ORD(3, flags=0x1) "3RD"', 'ORD(21, flags=0x2) "21st"'], tokens("3RD 21st")
    assert_equal :unknown_word, L.lex("3rdx").code
  end

  def test_a_long_number_keeps_its_first_nine_digits
    assert_equal ['NUM(123456789, flags=0xd) "1234567890123"'], tokens("1234567890123")
  end

  # The grammar reads `@t[i + 1] == :of` as the word "of", so a function word's Symbol is no other kind's value
  def test_function_word_symbols_belong_to_words_alone
    entries = Acute::Tables::WORDS.values + Acute::Tables::PHRASES.values
    words = entries.select { |kind, _| kind == :word }.map(&:last)
    others = entries.reject { |kind, _| kind == :word }.map(&:last)
    assert_empty words & others
  end

  def test_d44_an_end_mark_after_the_phrase_is_dropped
    assert_equal ['DAY(1) "tomorrow"'], tokens("tomorrow?! ")
    assert_raises(Acute::ParseError) { Acute.parse!("tomorrow? 5pm") }
  end

  def test_unicode_inside_and_between_words
    assert_equal ['WORD(half) "½"', 'UNIT(hour) "hour"'], tokens("½ hour")
    assert_equal Acute::Failure.new(:unknown_word, 0, 6), L.lex("hour½")
    assert_equal Acute::Failure.new(:unknown_word, 0, 5), L.lex("x’s")
    assert_equal ['MER(0) "am"', 'DAY(1) "tomorrow"'], tokens("10am tomorrow")[1, 2]
  end

  def test_a_phrase_and_its_first_word_alone
    assert_equal ['HOLIDAY(whit_monday) "monday of the holy spirit"'], tokens("monday of the holy spirit")
    assert_equal ['WDAY(1) "monday"', 'WORD(of) "of"', 'MONTH(5, flags=0x80) "may"'], tokens("monday of may")
  end

  def test_d45_a_unicode_dash_ends_a_word
    assert_equal ['MER(0) "am"', 'DASH(0) "–"'], tokens("10am–2pm")[1, 2]
    assert_equal("2026-10-17 22:00:00 -04:00/2026-10-18 00:00:00 -04:00",
                 parse("today, 10pm–12am").then { "#{wall(_1.begin)}/#{wall(_1.end)}" })
  end
end
