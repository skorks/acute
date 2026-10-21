require_relative "../test_helper"
require "json"

# Text that isn't UTF-8 fails as a value, in strict and lenient parsing alike
class EncodingTest < Minitest::Test
  AT = { now: "2026-10-17T14:00", zone: NY }.freeze
  MODES = [{}, { strict: false }].freeze
  BAD = ["tomorrow \xff", "\xfftomorrow", "tomorrow".encode("UTF-16LE"), "tomorrow".encode("UTF-16BE"),
         "tomorrow \xE9".dup.force_encoding("ISO-8859-1"), "caf\xE9".b].freeze

  def test_invalid_text_gives_nil_everywhere
    BAD.each do |text|
      MODES.each do |opts|
        assert_nil Acute.parse(text, **AT, **opts), text.inspect
        assert_nil Acute.read(text, **AT, **opts), text.inspect
        assert_nil Acute.duration(text, **opts), text.inspect
      end
    end
  end

  def test_parse_bang_explains
    BAD.each do |text|
      MODES.each do |opts|
        e = assert_raises(Acute::ParseError, text.inspect) { Acute.parse!(text, **AT, **opts) }
        assert_equal :invalid_encoding, e.code
        assert_match(/not valid UTF-8/, e.message)
      end
      assert_equal :invalid_encoding, assert_raises(Acute::ParseError) { Acute.duration!(text) }.code
    end
  end

  def test_a_lenient_result_always_serialises
    ["tomorrow ok", "tomorrow \xff", "\xfftomorrow"].each do |text|
      r = Acute.parse(text, **AT, strict: false)
      assert_equal text.valid_encoding?, !r.nil?
      JSON.parse(r.to_json) if r
    end
  end

  def test_text_in_a_compatible_encoding_is_accepted
    assert_equal Date.new(2026, 10, 18), Acute.parse("tomorrow".b, **AT).date
    assert_equal Date.new(2026, 10, 18), Acute.parse("tomorrow".encode("US-ASCII"), **AT).date
    assert_equal Date.new(2026, 10, 18), Acute.parse("tomorrow".dup.force_encoding("ISO-8859-1"), **AT).date
    assert_equal 3600, Acute.duration("1 hour".b).seconds
    assert_equal "tomorrow", Acute.parse("café tomorrow".b, **AT, strict: false).matched
  end
end
