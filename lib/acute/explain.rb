require_relative "errors"
require_relative "lexer"
require_relative "tables/words"

module Acute
  # Turns a Failure into a ParseError with a message, character positions and a hint. Only the error
  # path comes here, so it can afford to rescan the text.
  module Explain
    def self.error(failure, text)
      first = chars(text, failure.start)...chars(text, failure.stop)
      slice = text.byteslice(failure.start, failure.stop - failure.start)
      case failure.code
      when :unknown_word
        words = Lexer.unknown_ranges(text).map { |r| text.byteslice(r.begin, r.size) }
        hint = suggest(words.first)
        noun = words.size == 1 ? "word" : "words"
        ParseError.new("unknown #{noun} #{words.map(&:inspect).join(", ")}", code: :unknown_word, position: first,
                       unknown: words, hint: hint && "did you mean #{hint.inspect}?")
      when :invalid_date
        ParseError.new("#{slice.inspect} is not a valid time", code: :invalid_date, position: first)
      when :incomplete
        ParseError.new("the phrase is incomplete", code: :incomplete, position: first)
      when :conflict
        ParseError.new("#{slice.inspect} doesn't fit with the rest of the phrase", code: :conflict, position: first)
      else
        ParseError.new("longer than #{MAX_LENGTH} characters", code: :too_long, position: first)
      end
    end

    def self.chars(text, byte) = text.byteslice(0, byte).length

    def self.letters(bytes) = bytes.inject(0) { |m, c| m | 1 << (c & 63) }

    HINTS = Ractor.make_shareable(Tables::HINT_WORDS.map { |w| [w, w.bytes, letters(w.bytes)] })

    # The closest known word within two edits, if it is close enough to be a likely typo
    def self.suggest(word)
      return unless word && word.ascii_only?
      a = word.downcase.bytes
      mask = letters(a)
      best = nil
      best_distance = 3
      HINTS.each do |candidate, b, m|
        next if (b.size - a.size).abs >= best_distance
        # each letter one word has and the other lacks costs an edit, so this bounds the distance from below
        next if (mask & ~m).to_s(2).count("1") >= best_distance || (m & ~mask).to_s(2).count("1") >= best_distance
        d = distance(a, b, best_distance)
        if d < best_distance && d < b.size / 2
          best = candidate
          best_distance = d
        end
      end
      best
    end

    # Optimal string alignment distance: Levenshtein plus adjacent transpositions, three rows at a time.
    # Gives up with limit once a whole row is at least limit, since the distance can only grow from there.
    def self.distance(a, b, limit = Float::INFINITY)
      before = nil
      prev = (0..b.size).to_a
      a.each_with_index do |ca, i|
        row = [i + 1]
        low = i + 1
        b.each_with_index do |cb, j|
          d = prev[j + 1] + 1
          d = row[j] + 1 if row[j] + 1 < d
          s = prev[j] + (ca == cb ? 0 : 1)
          d = s if s < d
          d = before[j - 1] + 1 if i > 0 && j > 0 && ca == b[j - 1] && a[i - 1] == cb && before[j - 1] + 1 < d
          row << d
          low = d if d < low
        end
        return limit if low >= limit
        before = prev
        prev = row
      end
      prev[b.size]
    end
  end
end
