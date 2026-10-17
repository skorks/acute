require_relative "../test_helper"

class GrammarTest < Minitest::Test
  G = Acute::Grammar
  S = Acute::Lexer::STRIDE

  def longest(s, **opts) = G.longest(Acute::Lexer.lex(s), **opts)

  def test_longest_finds_the_longest_phrase_prefix
    tree, size = longest("tomorrow at 5pm 6 months")
    assert_equal 4 * S, size
    assert_equal G::Within, tree.class
  end

  def test_longest_is_nil_when_no_prefix_is_a_phrase
    assert_nil longest("of the")
  end

  def test_longest_duration
    units, size = longest("6 months tomorrow", duration: true)
    assert_equal 2 * S, size
    refute_nil units
    assert_nil longest("tomorrow", duration: true)
  end
end
