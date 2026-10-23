require_relative "../acute"
require_relative "numerize"

# numerizer 0.2.0's API on acute's lexer: number words, ordinals and fractions in a text become digits, and the
# rest of the text is kept byte for byte. The words are acute's, so a few answers differ from the gem's (D46).
class Numerizer
  def self.numerize(string) = Acute::Numerize.call(string)
end
