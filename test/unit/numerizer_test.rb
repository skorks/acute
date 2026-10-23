require "json"
require "yaml"
require_relative "../test_helper"
require_relative "../../lib/acute/numerizer"

# numerizer 0.2.0's answers, recorded by test/numerizer/record.rb, against acute's; where they differ, the cause is
# in test/numerizer/differences.yml (D46)
class NumerizerTest < Minitest::Test
  DIR = File.expand_path("../numerizer", __dir__)
  FIXTURE = File.readlines(File.join(DIR, "fixture.jsonl")).map { JSON.parse(_1) }
  DIFFERENCES = YAML.load_file(File.join(DIR, "differences.yml")).flat_map { _1["cases"] }

  def test_answers_as_numerizer_does_but_where_listed
    listed = DIFFERENCES.to_h { |input, _, acute| [input, acute] }
    unlisted = FIXTURE.filter_map do |input, numerizer|
      acute = Numerizer.numerize(input)
      [input, numerizer, acute] if acute != numerizer && !listed.key?(input)
    end
    assert_empty unlisted.map { JSON.generate(_1) }, "acute differs from numerizer; fix it or list it with its cause"
  end

  def test_each_listed_difference_still_differs
    answers = FIXTURE.to_h
    stale = DIFFERENCES.reject do |input, numerizer, acute|
      answers[input] == numerizer && Numerizer.numerize(input) == acute
    end
    assert_empty stale.map { JSON.generate(_1) }, "these no longer differ as listed; update or drop them"
  end

  def test_numbers_said_in_words
    {
      "forty two" => "42", "twenty-fourth" => "24th", "three quarters" => "3/4", "two and a half" => "2.5",
      "a hundred and five" => "105", "two thousand and eighteen" => "2018", "ten thousand and 5 hundred" => "10500",
      "one hundredth" => "100th", "five eighths" => "5/8", "zero" => "0", "twelve zero three" => "12 0 3",
      "3 and a half" => "3.5", "three 1/2" => "3.5", "2005 third quarter" => "2005 3rd quarter",
      "second" => "second", "a second" => "a second", "7 days" => "7 days", "a thousand and, five" => "1000 and, 5"
    }.each { |text, digits| assert_equal digits, Numerizer.numerize(text), text }
  end

  def test_every_other_byte_is_kept
    assert_equal "ça va 1, é 2!\t3\n", Numerizer.numerize("ça va one, é two!\tthree\n")
    assert_equal "  20  ", Numerizer.numerize("  Twenty  ")
  end

  def test_returns_a_new_string
    text = "no numbers here"
    refute_same text, Numerizer.numerize(text)
    assert_equal text, Numerizer.numerize(text)
  end
end
