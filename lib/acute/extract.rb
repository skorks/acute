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

    # The text without its mentions, nor the "on", "at", "for", "by" or "in" left dangling before one (E4)
    def remainder
      out = +""
      at = 0
      @mentions.each do |m|
        out << @text[at...m.offset.begin].sub(/(?:\b(?:on|at|for|by|in)\s*)+\z/i, "")
        at = m.offset.end
      end
      out << @text[at..]
      out.gsub(/\s+/, " ").gsub(/\s+([,.;])/, '\1').gsub(/\A[\s,;]+|[\s,;]+\z/, "")
    end

    def to_h
      { kind: "extraction", text: @text, remainder: remainder,
        mentions: @mentions.map { |m| { kind: m.kind.to_s, text: m.text, offset: [m.offset.begin, m.offset.end], value: m.value.to_h } } }
    end

    def to_json(*args) = to_h.to_json(*args)

    def as_json(*) = JSON.parse(to_json)
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
          found = starts_mention?(text, tokens, i) &&
                  longest(text, tokens[(i * S)...(w * S)], make_context, whole, spent)
          if found
            k = i
            look = ->(n) { longest(text, tokens[(n * S)...(w * S)], make_context, whole, spent) }
            # D51: "for 3 days from today" is a span with its "for", where "3 days from today" is a shift
            if i > a && tokens[(i - 1) * S] == L::WORD && tokens[(i - 1) * S + 1] == :for && (with = look.(i - 1)) &&
               with[0].kind == :time && with[0].offset.end >= found[0].offset.end && !same?(with[0].value, found[0].value)
              found = with
              k = i - 1
            end
            # E4: a leading "in", or a meal before "at" (D50), is left out when the rest reads the same, or
            # when the rest reaches further (D50): "in 2 days from today" is "2 days from today". D51: so are
            # "about" and "within" when the rest reaches further
            while (lead = LEADS[tokens[k * S]]&.[](tokens[k * S + 1])) && (tokens[k * S] == L::WORD || tokens[(k + 1) * S] == L::AT)
              shorter = after_lead(text, tokens, k, found, lead == :same, look)
              break unless shorter
              found, k = shorter
            end
            # D51: a bare number ending a mention goes with what follows when it starts a mention that reaches
            # further: "11/20, 12 of Nov"
            last = k + found[1] / S - 1
            if last > k && last + 1 < w && tokens[last * S] == L::NUM && tokens[last * S + 2] & L::DIGITS <= 2 &&
               !GLUE[tokens[(last - 1) * S]] && (after = look.(last)) && after[1] > S &&
               (shorter = longest(text, tokens[(k * S)...(last * S)], make_context, whole, spent))
              found = shorter
            end
            mentions << found[0]
            i = k + found[1] / S
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
        found = !glued?(all, j) && !trailing?(tokens, j) && !before_month?(all, j) &&
                mention(text, slice, j == t ? tree : nil, j == d ? units : nil, make_context, whole)
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
        next if k < n && !split?(text, tokens, k, gaps)
        out << [a, k]
        a = k
      end
      out
    end

    def self.split?(text, tokens, k, gaps)
      from = tokens[(k - 1) * S + 4]
      to = tokens[k * S + 3]
      gaps.shift while gaps.any? && gaps[0] < from
      return true if gaps.any? && gaps[0] < to
      dot = abbreviated?(text, tokens, k - 1) && !capital?(text.getbyte(to)) ? from : -1
      (from...to).any? { |b| (c = text.getbyte(b)) != 44 && b != dot && PUNCT.include?(c) }
    end

    ABBREVIATED = { L::MONTH => true, L::WDAY => true, L::MER => true }.freeze

    # E5: a dot right after a month, weekday or meridiem ends its abbreviation, not the sentence: "Oct. 2",
    # "1p.m. to 4". One before a capital still ends the sentence.
    def self.abbreviated?(text, tokens, k)
      ABBREVIATED[tokens[k * S]] && text.getbyte(tokens[k * S + 4]) == 46
    end

    def self.capital?(byte) = byte && byte >= 65 && byte <= 90

    START_WORDS = { on: true, and: true, to: true, for: true, during: true }.freeze
    LEADS = { L::WORD => { in: :same, around: :further, within: :further }.freeze,
              L::PART => { lunch: :same, breakfast: :same, dinner: :same }.freeze }.freeze

    # The mention inside found after its leading word at k, with where it starts: with same, the next one
    # when it reads the same or reaches further; otherwise the first that reaches further
    def self.after_lead(text, tokens, k, found, same, look)
      ((k + 1)...(k + found[1] / S)).each do |n|
        next unless starts_mention?(text, tokens, n)
        m = look.(n)
        return [m, n] if m && (m[0].offset.end > found[0].offset.end ||
                               (same && m[0].offset.end == found[0].offset.end && same?(m[0].value, found[0].value)))
        break if same
      end
      nil
    end

    # "on", "at", "for" and "during" introduce a mention without being part of it (E2 gives a duration its
    # "for", E4 leaves out "on" and "at"). None starts inside a written number, as "12-1234" in "123-12-1234"
    # or "1 in the morning" in "37.1 in the morning".
    def self.starts_mention?(text, tokens, i)
      k = tokens[i * S]
      if i >= 2 && GLUE[tokens[(i - 1) * S]] && tokens[(i - 2) * S] == L::NUM &&
         tokens[(i - 2) * S + 4] == tokens[(i - 1) * S + 3] && tokens[(i - 1) * S + 4] == tokens[i * S + 3]
        return false
      end
      return false if k == L::AT || (k == L::WORD && START_WORDS[tokens[i * S + 1]])
      return false if after?(text, tokens[i * S + 3], CURRENCY) # D50: "$12", "$DEC"
      return false if k == L::PART && after?(text, tokens[i * S + 3], GREETING) # D50: "Good morning"
      # D50: "start" and "end" in lower case are verbs unless "of" follows: "start 3 minutes from now"
      return false if k == L::FUZZ && tokens[i * S + 2] & L::CAP == 0 &&
                      VERBS.match?(text.byteslice(tokens[i * S + 3], tokens[i * S + 4] - tokens[i * S + 3])) &&
                      !(tokens[(i + 1) * S] == L::WORD && tokens[(i + 1) * S + 1] == :of)
      true
    end

    VERBS = /\A(?:start|end)\z/
    CURRENCY = /[$£€]\s*\z/
    GREETING = /\bgood\s+\z/i

    # Whether the text just before the byte matches
    def self.after?(text, byte, pattern)
      byte > 0 && text.byteslice([byte - 12, 0].max, [byte, 12].min).match?(pattern)
    end

    TRAILING = { on: true, the: true, at: true, and: true, of: true, to: true, in: true, for: true, by: true }.freeze

    # D50: a mention doesn't end in a word that only introduces what follows: "May 6th 2004, the customer"
    def self.trailing?(tokens, j)
      j > S && tokens[j - S] == L::WORD && TRAILING[tokens[j - S + 1]]
    end

    # D50: a month abbreviation directly before another month is a name: "Angie Mar November 2019"
    def self.before_month?(all, j)
      j == S && all[0] == L::MONTH && all[j] == L::MONTH && all[4] - all[3] <= 3
    end

    # E4: the same begin and end for every reading, and the same alternatives
    def self.same?(a, b)
      return a == b unless a.kind == :time && b.kind == :time
      [a, *a.alternatives].map { |r| [r.begin, r.end] } == [b, *b.alternatives].map { |r| [r.begin, r.end] }
    end

    # Nor does one end inside a written number, as "2010-2015" in "2010-2015-86"
    def self.glued?(tokens, j)
      j + S < tokens.size && GLUE[tokens[j]] && tokens[j - S] == L::NUM && tokens[j + S] == L::NUM &&
        tokens[j - 1] == tokens[j + 3] && tokens[j + 4] == tokens[j + S + 3]
    end

    def self.mention(text, slice, tree, units, make_context, whole)
      st = slice[3]
      return if plain_english?(slice, sentence_start?(text, st)) || (slice.size == S && slice[0] == L::NUM) ||
                spelled?(slice) || in_word?(text, st, slice[-1]) || one_to_one?(slice) || counted?(text, slice)
      stop = meridiem_dot(text, slice) || slice[-1]
      # E5: "'40s": the apostrophe for the century left out is part of it
      st -= 1 if slice[0] == L::DECADE && st > 0 && text.getbyte(st - 1) == 39
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

    # E5: "4 a.m.", "3 p . m .": the last dot of a meridiem written with dots is part of it
    def self.meridiem_dot(text, slice)
      return unless slice[-S] == L::MER && (abbr = text.byteslice(slice[-2], slice[-1] - slice[-2])).include?(".")
      dot = abbr.include?(" ") ? space_after(text, slice[-1]) : slice[-1]
      dot + 1 if text.getbyte(dot) == 46
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

    JOINS = { to: true, and: true, or: true }.freeze

    # D50: numbers written as words with no time word beside them are plain English: "two to four people",
    # "One may ask", "The first free fish"
    def self.spelled?(slice)
      tokens = slice.each_slice(S).to_a
      words, content = tokens.partition { |k, *| k == L::WORD || k == L::ART }
      spelled = ->((k, _, flags)) { (k == L::NUM || k == L::ORD) && flags & L::WORDY != 0 }
      if content.all?(&spelled)
        content.size == 1 ? content[0][0] == L::ORD && words.all? { |_, v| v == :the } : words.any? && words.all? { |_, v| JOINS[v] }
      else
        words.empty? && content.size == 2 && spelled.(content[0]) && content[1][2] & (L::ENGLISH | L::CAP) == L::ENGLISH
      end
    end

    # D50: nothing inside a word or an id: "3am" in "~.~3am3ioYcY0"
    def self.in_word?(text, st, stop)
      (st > 0 && alnum?(text.getbyte(st - 1))) || alnum?(text.getbyte(stop))
    end

    def self.alnum?(byte) = byte && ((byte >= 48 && byte <= 57) || ((byte | 32) >= 97 && (byte | 32) <= 122))

    # D50: the same number at both ends is no range: "a 1-1 meeting"
    def self.one_to_one?(slice)
      slice.size == 3 * S && slice[0] == L::NUM && slice[S] == L::DASH && slice[2 * S] == L::NUM && slice[1] == slice[2 * S + 1]
    end

    # D50: an ordinal before "time" or "times" counts occasions: "17th times", "the 5th time"
    def self.counted?(text, slice)
      slice.each_slice(S).count { |k, *| k != L::WORD && k != L::ART } == 1 && slice[-S] == L::ORD &&
        text.byteslice(slice[-1], 8).match?(/\A\s+times?\b/i)
    end

    SPACE = [32, 9, 10, 11, 12, 13].freeze

    def self.space_before(text, byte)
      byte -= 1 while byte > 0 && SPACE.include?(text.getbyte(byte - 1))
      byte
    end

    def self.space_after(text, byte)
      byte += 1 while byte < text.bytesize && SPACE.include?(text.getbyte(byte))
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
