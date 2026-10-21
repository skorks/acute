module Acute
  # Times and durations mentioned inside prose. Lexing is lenient: unknown words split the text into runs of
  # known ones. Each run is cut into the longest pieces the strict grammar accepts, leftmost first (E2, E3).
  class Extraction
    # offset: a character Range into the text; value: a Result or a Duration
    Mention = Struct.new(:kind, :text, :offset, :value)

    attr_reader :text, :mentions

    def initialize(text, mentions)
      @text = text
      @mentions = mentions.freeze
    end

    # The text without its mentions, nor the "on", "at", "for" or "by" left dangling before one
    def remainder
      out = +""
      at = 0
      @mentions.each do |m|
        out << @text[at...m.offset.begin].sub(/\b(?:on|at|for|by)\s*\z/i, "")
        at = m.offset.end
      end
      out << @text[at..]
      out.gsub(/\s+/, " ").gsub(/\s+([,.;])/, '\1').gsub(/\A[\s,;]+|[\s,;]+\z/, "")
    end
  end

  module Extract
    L = Lexer
    S = Lexer::STRIDE
    PUNCT = [44, 46, 59, 33, 63].freeze
    GLUE = { L::DASH => true, L::SLASH => true, L::DOT => true }.freeze
    BUDGET = 20_000
    FEW = 8

    # whole: the text each Result is for, when it is not the mention's own (parse with strict: false)
    def self.call(text, make_context, whole = nil)
      text = text.scrub unless text.valid_encoding?
      unknown = []
      tokens = Lexer.lex(text, unknown)
      mentions = []
      from = Chars.new(text)
      to = Chars.new(text)
      spent = [0]
      budget = BUDGET + 32 * tokens.size
      runs(text, tokens, unknown).each do |a, b|
        i = a
        e = a
        while i < b
          # No mention is longer than a phrase parse takes, so the grammar sees no more than that
          start = from[tokens[i * S + 3]]
          e = i + 1 if e <= i
          e += 1 while e < b && to[tokens[e * S + 4]] - start <= MAX_LENGTH
          # Text that makes every start parse far and fail, as "the the the…", has the grammar see a few words
          # at each once it has cost far more than prose does
          w = spent[0] > budget && e > i + FEW ? i + FEW : e
          found = starts_mention?(tokens, i) &&
                  longest(text, tokens[(i * S)...(w * S)], make_context, whole, spent)
          if found
            mentions << found[0]
            i += found[1] / S
          else
            i += 1
          end
        end
      end
      chars = Chars.new(text)
      mentions.each { |m| m.offset = chars[m.offset.begin]...chars[m.offset.end] }
      Extraction.new(text, mentions)
    end

    # Character offsets of byte offsets, counted from the last one asked for: a walk through the text costs
    # its length once
    class Chars
      def initialize(text)
        @text = text
        @ascii = text.ascii_only?
        @byte = 0
        @char = 0
      end

      def [](byte)
        return byte if @ascii
        @char += byte >= @byte ? @text.byteslice(@byte, byte - @byte).length : -@text.byteslice(byte, @byte - byte).length
        @byte = byte
        @char
      end
    end

    # The longest mention at the start of the tokens, as [mention, its length in entries]. Only the prefixes
    # the grammar accepts are tried, longest first: a phrase's, then a duration's.
    def self.longest(text, all, make_context, whole, spent)
      tokens = all
      until tokens.empty?
        tree, t = Grammar.longest(tokens, spent:)
        units, d = Grammar.longest(tokens, duration: true, spent:)
        return unless tree || units
        j = t.to_i > d.to_i ? t : d
        slice = j == tokens.size ? tokens : tokens[0, j]
        found = !glued?(all, j) && mention(text, slice, j == t ? tree : nil, j == d ? units : nil, make_context, whole)
        return [found, j] if found
        tokens = tokens[0, j - S]
      end
    end

    # Token index ranges [a, b) not split by an unknown word or a sentence's punctuation
    def self.runs(text, tokens, unknown)
      gaps = unknown.each_slice(2).map(&:first)
      out = []
      a = 0
      n = tokens.size / S
      (1..n).each do |k|
        next if k < n && !split?(text, tokens[(k - 1) * S + 4], tokens[k * S + 3], gaps)
        out << [a, k]
        a = k
      end
      out
    end

    def self.split?(text, from, to, gaps)
      gaps.shift while gaps.any? && gaps[0] < from
      return true if gaps.any? && gaps[0] < to
      text.byteslice(from, to - from).each_byte.any? { |c| PUNCT.include?(c) && c != 44 }
    end

    START_WORDS = { on: true, and: true, to: true, for: true, during: true }.freeze

    # "on", "at", "for" and "during" introduce a mention without being part of it (E2 gives a duration its
    # "for"). None starts inside a written number, as "12-1234" in "123-12-1234" or "1 in the morning" in
    # "37.1 in the morning".
    def self.starts_mention?(tokens, i)
      k = tokens[i * S]
      if i >= 2 && GLUE[tokens[(i - 1) * S]] && tokens[(i - 2) * S] == L::NUM &&
         tokens[(i - 2) * S + 4] == tokens[(i - 1) * S + 3] && tokens[(i - 1) * S + 4] == tokens[i * S + 3]
        return false
      end
      k != L::AT && !(k == L::WORD && START_WORDS[tokens[i * S + 1]])
    end

    # Nor does one end inside a written number, as "2010-2015" in "2010-2015-86"
    def self.glued?(tokens, j)
      j + S < tokens.size && GLUE[tokens[j]] && tokens[j - S] == L::NUM && tokens[j + S] == L::NUM &&
        tokens[j - 1] == tokens[j + 3] && tokens[j + 4] == tokens[j + S + 3]
    end

    def self.mention(text, slice, tree, units, make_context, whole)
      st = slice[3]
      return if plain_english?(slice, sentence_start?(text, st)) || (slice.size == S && slice[0] == L::NUM)
      stop = slice[-1]
      piece = text.byteslice(st, stop - st)
      value = (tree && time(piece, tree, make_context, whole)) || (units && Duration.from_units(units))
      return unless value
      # E2: "for 2 hours" is the duration's mention, "for" included
      if value.kind == :duration && (f = for_before(text, st))
        st = f
        piece = text.byteslice(st, stop - st)
      end
      Extraction::Mention.new(value.kind, piece, st...stop, value)
    end

    def self.time(piece, tree, make_context, whole)
      ctx = make_context.()
      readings = Resolve.call(tree, ctx)
      Result.new(whole || piece, readings, ctx.zone, ctx.assumptions(readings[0]), piece) unless readings.empty?
    end

    # E3: "may", "sat", "second" in lower case and with nothing else to say they are times are words. A
    # capital that starts a sentence says nothing, so "Lunch with Sam" is a word too.
    def self.plain_english?(slice, sentence_start)
      content = slice.each_slice(S).reject { |k, *| k == L::WORD || k == L::REL || k == L::ART || k == L::AT }
      content.any? && content.each_with_index.all? do |(_, _, flags, start), n|
        flags & L::ENGLISH != 0 && (flags & L::CAP == 0 || (n == 0 && sentence_start && start == slice[3]))
      end
    end

    SPACE = [32, 9, 10, 11, 12, 13].freeze

    def self.space_before(text, byte)
      byte -= 1 while byte > 0 && SPACE.include?(text.getbyte(byte - 1))
      byte
    end

    def self.sentence_start?(text, byte)
      byte = space_before(text, byte)
      byte == 0 || [46, 33, 63].include?(text.getbyte(byte - 1))
    end

    # Where the "for" just before the byte starts, with a space or more between
    def self.for_before(text, byte)
      word = space_before(text, byte)
      return if word == byte || word < 3 || !text.byteslice(word - 3, 3).casecmp?("for")
      return 0 if word == 3
      before = word - 4
      before -= 1 while before > 0 && text.getbyte(before) & 0xC0 == 0x80
      word - 3 unless text.byteslice(before, word - 3 - before).match?(/\p{Word}/)
    end
  end
end
