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

    def self.call(text, make_context)
      unknown = []
      tokens = Lexer.lex(text, unknown)
      mentions = []
      runs(text, tokens, unknown).each do |a, b|
        i = a
        while i < b
          found = starts_mention?(tokens, i) && longest(text, tokens[i * S...b * S], make_context)
          if found
            mentions << found[0]
            i += found[1] / S
          else
            i += 1
          end
        end
      end
      Extraction.new(text, mentions)
    end

    # The longest mention at the start of the tokens, as [mention, its length in entries]. Only the prefixes
    # the grammar accepts are tried, longest first: a phrase's, then a duration's.
    def self.longest(text, tokens, make_context)
      while tokens.size > 0
        tree, t = Grammar.longest(tokens)
        units, d = Grammar.longest(tokens, duration: true)
        return unless tree || units
        j = t.to_i > d.to_i ? t : d
        slice = j == tokens.size ? tokens : tokens[0, j]
        found = mention(text, slice, j == t ? tree : nil, j == d ? units : nil, make_context)
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
      return true if gaps.any? { |g| g >= from && g < to }
      text.byteslice(from, to - from).each_byte.any? { |c| PUNCT.include?(c) && c != 44 }
    end

    # "on" and "at" introduce a mention without being part of it. None starts inside a written number, as
    # "12-1234" in "123-12-1234" or "1 in the morning" in "37.1 in the morning".
    def self.starts_mention?(tokens, i)
      k = tokens[i * S]
      if i >= 2 && GLUE[tokens[(i - 1) * S]] && tokens[(i - 2) * S] == L::NUM &&
         tokens[(i - 2) * S + 4] == tokens[(i - 1) * S + 3] && tokens[(i - 1) * S + 4] == tokens[i * S + 3]
        return false
      end
      k != L::AT && !(k == L::WORD && (tokens[i * S + 1] == :on || tokens[i * S + 1] == :and || tokens[i * S + 1] == :to))
    end

    def self.mention(text, slice, tree, units, make_context)
      st = slice[3]
      return if plain_english?(slice, sentence_start?(text, st)) || (slice.size == S && slice[0] == L::NUM)
      stop = slice[-1]
      piece = text.byteslice(st, stop - st)
      value = (tree && time(piece, tree, make_context)) || (units && Duration.from_units(units))
      return unless value
      # E2: "for 2 hours" is the duration's mention, "for" included
      if value.kind == :duration && (m = text.byteslice(0, st).match(/\bfor\s+\z/i))
        st = m.begin(0)
        piece = text.byteslice(st, stop - st)
      end
      Extraction::Mention.new(value.kind, piece, chars(text, st)...chars(text, stop), value)
    end

    def self.time(piece, tree, make_context)
      ctx = make_context.()
      readings = Resolve.call(tree, ctx)
      Result.new(piece, readings, ctx.zone, ctx.assumptions(readings[0])) unless readings.empty?
    end

    # E3: "may", "sat", "second" in lower case and with nothing else to say they are times are words. A
    # capital that starts a sentence says nothing, so "Lunch with Sam" is a word too.
    def self.plain_english?(slice, sentence_start)
      content = slice.each_slice(S).reject { |k, *| k == L::WORD || k == L::REL || k == L::ART || k == L::AT }
      content.any? && content.each_with_index.all? do |(_, _, flags, start), n|
        flags & L::ENGLISH != 0 && (flags & L::CAP == 0 || (n == 0 && sentence_start && start == slice[3]))
      end
    end

    def self.sentence_start?(text, byte) = text.byteslice(0, byte).match?(/(?:\A|[.!?])\s*\z/)

    def self.chars(text, byte) = text.ascii_only? ? byte : text.byteslice(0, byte).length
  end
end
