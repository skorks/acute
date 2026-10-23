module Acute
  # Times and durations mentioned inside prose. Lexing is lenient: unknown words split the text into runs of
  # known ones. Each run is cut into the longest pieces the strict grammar accepts, leftmost first (E2, E3).
  class Extraction
    # offset: a character Range into the text; value: a Result, a Duration or a Rule
    Mention = Data.define(:kind, :text, :offset, :value)

    attr_reader :text, :mentions

    # @api private
    def initialize(text, mentions)
      @text = text
      @mentions = mentions.freeze
      freeze
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

  # @api private
  module Extract
    L = Lexer
    S = Lexer::STRIDE
    PUNCT = [44, 46, 59, 33, 63].freeze
    GLUE = { L::DASH => true, L::SLASH => true, L::DOT => true }.freeze
    BUDGET = 20_000
    FEW = 8

    # whole: the text each Result is for, when it is not the mention's own (parse with strict: false)
    def self.call(text, make_context, whole = nil)
      unknown = []
      tokens = Lexer.lex(lexable(text), unknown)
      listed_days(text, tokens)
      mentions = []
      from = Chars.new(text)
      to = Chars.new(text)
      spent = [0]
      budget = BUDGET + 32 * tokens.size
      runs(text, tokens, unknown).each do |a, b|
        i = a
        e = a
        # The words in the run that make a rule. Lenient parse (whole) wants a time, so it looks for none.
        marks = whole ? [] : (a...b).select { |k| Grammar.rule?(tokens[k * S, S]) || hours_mark?(tokens, a, k) }
        while i < b
          # No mention is longer than a phrase parse takes, so the grammar sees no more than that
          start = from[tokens[i * S + 3]]
          e = i + 1 if e <= i
          e += 1 while e < b && to[tokens[e * S + 4]] - start <= MAX_LENGTH
          # Text that makes every start parse far and fail, as "the the the…", has the grammar see a few words
          # at each once it has cost far more than prose does
          w = spent[0] > budget && e > i + FEW ? i + FEW : e
          starts = starts_mention?(text, tokens, i)
          found = starts && longest(text, tokens[(i * S)...(w * S)], make_context, whole, spent)
          marks.shift while marks.any? && marks[0] < i
          rule = starts && marks.any? && marks[0] < w && rule_at(text, tokens, i, w, marks[0], make_context, spent)
          if rule && (!found || rule[0].offset.end >= found[0].offset.end)
            mentions << rule[0]
            i = rule[1]
          elsif found
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
          elsif tokens[i * S] == L::NUM && tokens[i * S + 2] & L::DIGITS == 4 && mentions.any? &&
                (year = joined_year(text, tokens, i, mentions[-1], make_context, whole, spent))
            mentions << year
            i += 1
          else
            i += 1
          end
        end
      end
      chars = Chars.new(text)
      mentions.map! { |m| m.with(offset: chars[m.offset.begin]...chars[m.offset.end]) }
      Extraction.new(text, mentions)
    end

    # T29: a run of what the lexer's word loop carries a word over (letters, an apostrophe, a dot before a
    # letter, a UTF-8 character but a space or dash), far too long to be a word: a URL, base64, CJK without
    # spaces. The loop packs a word into one Integer, a bignum multiply a byte by then, so 64 KB of one took
    # 0.6 s. parse and the rest reject text over MAX_LENGTH first; extract has the run's middle blanked
    # for the lexer, byte for byte, so every offset stays and its ends still lex as the unknown words they were.
    NOT_SPACE = "\\x00-\\x7F\\u00A0\\u2000-\\u200A\\u202F\\u205F\\u3000\\u2010-\\u2015\\u2212".freeze
    LONG = /(?:[A-Za-z']|[^#{NOT_SPACE}\u00BD\u2019])(?:[A-Za-z']|\.(?=[A-Za-z])|[^#{NOT_SPACE}]){63,}/
    KEEP = 24 # characters at each end, more than the longest word's 14

    def self.lexable(text)
      return text unless LONG.match?(text)
      text.gsub(LONG) do |run|
        head = run[0, run[KEEP - 1] == "." ? KEEP + 1 : KEEP] # a dot before a space would lex as a dot
        tail = run[-KEEP..].sub(/\A[.½]+/, "") # so would a dot or "½" after one
        head + (" " * (run.bytesize - head.bytesize - tail.bytesize)) + tail
      end
    end

    SPAN_WORDS = { to: true, through: true, till: true, until: true }.freeze
    HEAD = 6 # tokens back that a span of days' "to" may be, as "oct 26 to oct 30"

    # R29: the "from" or "between" of "monday to friday from 9 to 5", a span of days with daily hours, which no
    # word that makes a rule marks: one after a "to", "through" or dash a few words back in the run
    def self.hours_mark?(tokens, a, k)
      return false unless tokens[k * S] == L::WORD && ((v = tokens[k * S + 1]) == :from || v == :between)
      ([a, k - HEAD].max...k).any? do |j|
        (t = tokens[j * S]) == L::DASH || (t == L::WORD && SPAN_WORDS[tokens[j * S + 1]])
      end
    end

    # The longest rule from token i, as [mention, the index after it]: the run up to w, then shorter, while it
    # keeps the rule word at mark and doesn't end in a word that only introduces what follows (D50)
    def self.rule_at(text, tokens, i, w, mark, make_context, spent)
      j = w
      FEW.times do
        j -= 1 while j > mark + 1 && tokens[(j - 1) * S] == L::WORD && TRAILING[tokens[(j - 1) * S + 1]]
        break if j <= mark
        next j -= 1 if glued?(tokens, j * S)
        slice = tokens[(i * S)...(j * S)]
        spent[0] += slice.size
        found = rule_mention(text, slice, make_context)
        return [found, j] if found
        j -= 1
      end
      nil
    end

    # D50: a number written as a word doesn't start one: "one every 8 hours" is "every 8 hours"
    # The grammar goes first: it says no the most cheaply, and hostile text has it asked at every word
    def self.rule_mention(text, slice, make_context)
      tree = Grammar.rule(slice)
      return if Failure === tree
      st = slice[3]
      return if plain_english?(slice, sentence_start?(text, st)) || in_word?(text, st, slice[-1]) ||
                adjective?(text, slice) || (slice[0] == L::NUM && slice[2] & L::WORDY != 0)
      stop = meridiem_dot(text, slice) || slice[-1]
      piece = text.byteslice(st, stop - st)
      value = Acute.send(:rule, piece, make_context.(), slice, tree)
      Extraction::Mention.new(:rule, piece, st...stop, value) if Rule === value
    end

    CONTINUES = %w[at with from until till for and or on in by to before after during through].freeze

    # E6: a lone frequency word before a noun-like word is an adjective: "hourly rate", "the weekly report". Not
    # before a word that goes on with a rule: "take it daily with food"
    def self.adjective?(text, slice)
      content = slice.each_slice(S).reject { |k, v| k == L::ART || (k == L::WORD && v == :the) }
      return false unless content.size == 1 && content[0][0] == L::WORD && Grammar::FREQUENCY[content[0][1]]
      return true if content.size < slice.size / S || determined?(text, slice[3]) || hyphenated?(text, slice[-1])
      at = space_after(text, slice[-1])
      at > slice[-1] && (c = text.getbyte(at)) && (c | 32).between?(97, 122) &&
        !CONTINUES.include?(text.byteslice(at, 12).scrub("")[/\A[a-z]+/i]&.downcase)
    end

    DETERMINERS = %w[the a an this our my your their his its].freeze

    # E6: "read the daily", "our weekly with the team": after a determiner it is a noun phrase
    # Walks back over the word byte by byte, no further than the longest determiner and one more: a regex on all
    # the text before would make extract quadratic
    def self.determined?(text, start)
      stop = space_before(text, start)
      word = stop
      word -= 1 while word > 0 && stop - word < 6 && letter?(text.getbyte(word - 1))
      stop < start && word < stop && !(word > 0 && letter?(text.getbyte(word - 1))) &&
        DETERMINERS.include?(text.byteslice(word, stop - word).downcase)
    end

    def self.letter?(byte) = (byte | 32).between?(97, 122)

    # E6: "to-do", "on-call": a word joined by a hyphen is a compound noun, not a word that continues a rule
    def self.hyphenated?(text, stop)
      text.getbyte(stop) == 45 && (c = text.getbyte(stop + 1)) && (c | 32).between?(97, 122)
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
      return false if k == L::NUM && after?(text, tokens[i * S + 3], LABEL) # D51: "building 4 this afternoon"
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
    LABEL = /\b(?:building|room|floor|level|gate|platform|terminal|suite|unit|table|track|bay|page|chapter)\s+\z/i

    # Whether the text just before the byte matches
    # The window can start inside a multibyte character, which a regex refuses to match: "会議は日本 tomorrow"
    def self.after?(text, byte, pattern)
      return false unless byte > 0
      before = text.byteslice([byte - 12, 0].max, [byte, 12].min)
      (before.valid_encoding? ? before : before.scrub("")).match?(pattern)
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
                spelled?(slice) || in_word?(text, st, slice[-1]) || one_to_one?(slice) || counted?(text, slice) ||
                version?(slice)
      stop = meridiem_dot(text, slice) || slice[-1]
      # E5: "'40s": the apostrophe for the century left out is part of it
      st -= 1 if slice[0] == L::DECADE && st > 0 && text.getbyte(st - 1) == 39
      piece = text.byteslice(st, stop - st)
      # D48: "[5pm] tomorrow", "lunch [5pm]": a mention that reads across one bracket takes the other too
      if st > 0 && text.getbyte(st - 1) == 91 && piece.include?("]")
        piece = text.byteslice(st -= 1, stop - st)
      elsif text.getbyte(stop) == 93 && piece.include?("[")
        piece = text.byteslice(st, (stop += 1) - st)
      end
      value = (tree && time(piece, tree, make_context, whole)) || (units && Duration.from_units(units))
      return unless value
      # E2: "for 2 hours" is the duration's mention, "for" included
      if value.kind == :duration && (f = for_before(text, st))
        st = f
        piece = text.byteslice(st, stop - st)
      end
      Extraction::Mention.new(value.kind, piece, st...stop, value)
    end

    JOINED = /\A\s*(?:and|or|(?:and |but )?not)\s+\z/
    YEAR_END = /\d{4}\z/

    # D51: a lone year joined by "and", "or" or "not" to a mention that ends in a year is a year too: "in 2007
    # and 2009", "before 2000 but not 1998". With no mention before it, a lone year is still a number (E3).
    def self.joined_year(text, tokens, i, last, make_context, whole, spent)
      st = tokens[i * S + 3]
      stop = tokens[i * S + 4]
      return unless last.text.match?(YEAR_END) && JOINED.match?(text.byteslice(last.offset.end, st - last.offset.end)) &&
                    !glued?(tokens, (i + 1) * S) && !in_word?(text, st, stop)
      slice = tokens[i * S, S]
      tree, = Grammar.longest(slice, spent:)
      piece = text.byteslice(st, stop - st)
      value = tree && time(piece, tree, make_context, whole)
      Extraction::Mention.new(value.kind, piece, st...stop, value) if value
    end

    LIST_GAP = /\A\s*(?:,\s*|(?:,\s*)?(?:and|or)\s+)\z/i

    # D18: a weekday in a list of weekdays is a day, though it is also a word: "mon, wed and fri", "mon and
    # wed" mention each day
    def self.listed_days(text, tokens)
      prev = nil
      (0...tokens.size).step(S) do |j|
        if tokens[j] == L::WDAY
          if prev && LIST_GAP.match?(text.byteslice(tokens[prev + 4], tokens[j + 3] - tokens[prev + 4]))
            tokens[prev + 2] &= ~L::ENGLISH
            tokens[j + 2] &= ~L::ENGLISH
          end
          prev = j
        elsif !(tokens[j] == L::WORD && ((w = tokens[j + 1]) == :and || w == :or))
          prev = nil
        end
      end
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
    # capital that starts a sentence says nothing, so "Lunch with Sam" is a word too. D51: a month after "in"
    # is a month: "It may be in may".
    def self.plain_english?(slice, sentence_start)
      return false if slice[0] == L::WORD && slice[1] == :in && slice[S] == L::MONTH
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

    # D51: three dotted numbers with a one-digit day or month and a two-digit year are a version: "1.5.30"
    def self.version?(slice)
      slice.size >= 5 * S && slice[S] == L::DOT && slice[3 * S] == L::DOT && slice[4 * S] == L::NUM &&
        slice[4 * S + 2] & L::DIGITS == 2 && slice[2] & L::DIGITS <= 2 &&
        (slice[2] & L::DIGITS == 1 || slice[2 * S + 2] & L::DIGITS == 1) &&
        slice[4] == slice[S + 3] && slice[S + 4] == slice[2 * S + 3] && slice[2 * S + 4] == slice[3 * S + 3] &&
        slice[3 * S + 4] == slice[4 * S + 3]
    end

    # D50: an ordinal before "time" or "times" counts occasions: "17th times", "the 5th time"
    def self.counted?(text, slice)
      slice.each_slice(S).count { |k, *| k != L::WORD && k != L::ART } == 1 && slice[-S] == L::ORD &&
        text.byteslice(slice[-1], 8).scrub("").match?(/\A\s+times?\b/i) # the 8 bytes can end inside a character
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
      return if word == byte || word < 3 || !text.byteslice(word - 3, 3).b.casecmp?("for")
      return 0 if word == 3
      before = word - 4
      before -= 1 while before > 0 && text.getbyte(before) & 0xC0 == 0x80
      word - 3 unless text.byteslice(before, word - 3 - before).match?(/\p{Word}/)
    end
  end

  private_constant :Extract
end
