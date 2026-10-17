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

    def self.call(text, make_context)
      unknown = []
      tokens = Lexer.lex(text, unknown)
      return Extraction.new(text, []) if Failure === tokens # a malformed clock ("25:99") stops the lexer
      mentions = []
      runs(text, tokens, unknown).each do |a, b|
        i = a
        while i < b
          found = starts_mention?(tokens, i) && b.downto(i + 1).lazy.filter_map { |j| mention(text, tokens, i, j, make_context) }.first
          if found
            mentions << found
            i = found[1]
          else
            i += 1
          end
        end
      end
      Extraction.new(text, mentions.map { _1[0] })
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

    # "on" and "at" introduce a mention without being part of it
    def self.starts_mention?(tokens, i)
      k = tokens[i * S]
      k != L::AT && !(k == L::WORD && (tokens[i * S + 1] == :on || tokens[i * S + 1] == :and || tokens[i * S + 1] == :to))
    end

    def self.mention(text, tokens, i, j, make_context)
      slice = tokens[i * S...j * S]
      st = slice[3]
      return if plain_english?(slice, sentence_start?(text, st)) || (j - i == 1 && slice[0] == L::NUM)
      stop = slice[-1]
      piece = text.byteslice(st, stop - st)
      value = time(piece, slice, make_context) || duration(slice)
      return unless value
      # E2: "for 2 hours" is the duration's mention, "for" included
      if value.kind == :duration && (m = text.byteslice(0, st).match(/\bfor\s+\z/i))
        st = m.begin(0)
        piece = text.byteslice(st, stop - st)
      end
      offset = chars(text, st)...chars(text, stop)
      [Extraction::Mention.new(value.kind, piece, offset, value), j]
    end

    def self.time(piece, slice, make_context)
      tree = Grammar.parse(slice)
      return if Failure === tree
      ctx = make_context.()
      readings = Resolve.call(tree, ctx)
      Result.new(piece, readings, ctx.zone, ctx.assumptions(readings[0])) unless readings.empty?
    end

    def self.duration(slice)
      units = Grammar.duration(slice)
      Duration.from_units(units) unless Failure === units
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
