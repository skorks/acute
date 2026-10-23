require_relative "../test_helper"

class GrammarTest < Minitest::Test
  G = Acute::Grammar
  S = Acute::Lexer::STRIDE

  def longest(s, **opts) = G.longest(Acute::Lexer.lex(s), **opts)

  def test_longest_finds_the_longest_phrase_prefix
    tree, size = longest("tomorrow at 5pm 6 months")
    assert_equal 4 * S, size
    assert_instance_of G::Within, tree
  end

  def test_d50_a_range_end_does_not_take_a_from_it_cannot_use
    _, size = longest("tomorrow through sunday from 9 to 5")
    assert_equal 3 * S, size
    assert_nil Acute.parse("tomorrow through sunday from", now: "2026-10-17T14:00", zone: NY)
    assert Acute.parse("friday from 9 to 5", now: "2026-10-17T14:00", zone: NY)
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
