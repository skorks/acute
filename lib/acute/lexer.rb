require_relative "errors"
require_relative "tables/words"

module Acute
  # Bytes to tokens. The result is one flat Array, STRIDE entries per token:
  # kind, value, flags, start, stop (byte offsets, stop exclusive). Failures come back as a Failure value.
  module Lexer
    STRIDE = 5

    NUM = 0     # value: the number; flags: digit count, ZERO, WORDY
    CLOCK = 1   # value: hhmmss as decimal digits; flags: hour digit count, ZERO, SECONDS
    MER = 2     # value: 0 for am, 12 for pm
    DAY = 3     # value: days from today
    NAMED = 4   # value: the hour named (noon 12, midnight 0)
    NOW = 5
    AT = 6
    WDAY = 7    # value: 0 = Sunday
    MONTH = 8   # value: 1-12
    UNIT = 9    # value: a Symbol (:day, :week, :business_day...)
    REL = 10    # value: :next, :this, :last or :past
    ORD = 11    # value: the number; "3rd" or "third"
    PART = 12   # value: :morning, :tonight...
    SEASON = 13
    HOLIDAY = 14
    WEEKEND = 15
    ZONE = 16   # value: UTC offset in seconds
    FUZZ = 17   # value: :early, :mid, :late, :start or :end
    ART = 18    # "a", "an"
    WORD = 19   # value: a Symbol for a function word (:in, :ago, :of...)
    SLASH = 20
    DASH = 21
    DOT = 22    # only between digits
    PLUS = 23
    DECADE = 24 # value: the number as written, 90 or 1990; flags: digit count, WORDY
    KIND_NAMES = Ractor.make_shareable(%w[NUM CLOCK MER DAY NAMED NOW AT WDAY MONTH UNIT REL ORD PART SEASON HOLIDAY WEEKEND ZONE FUZZ ART
                    WORD SLASH DASH DOT PLUS DECADE])

    DIGITS = 15
    ZERO = 16
    SECONDS = 32
    WORDY = 64     # a number or ordinal written as a word
    ENGLISH = 128  # also an ordinary English word ("may", "sat", "second"), for extraction
    CAP = 256      # written with a capital
    SHORT = 512    # two digits after an apostrophe: a year with its century left out, "'26"
    PLURAL = 1024  # "fridays": only after a count

    KINDS = {
      day: DAY, meridiem: MER, named: NAMED, now: NOW, at: AT, weekday: WDAY, month: MONTH, unit: UNIT,
      relative: REL, number: NUM, ordinal: ORD, part: PART, season: SEASON, holiday: HOLIDAY, weekend: WEEKEND,
      zone: ZONE, fuzzy: FUZZ, article: ART, word: WORD, decade: DECADE
    }.freeze

    # A word packs into an Integer, 5 bits a character, so lookup needs no substring
    def self.pack(word) = word.each_byte.reduce(0) { |k, c| k * 32 + code(c) }

    def self.code(c)
      if c >= 97 then c - 96
      elsif c == 46 then 27
      else 28
      end
    end

    # [kind, value, flags, whether it is "one" to "nine" or "first" to "ninth", which join a "twenty" before them]
    def self.entry(word, kind, value)
      kind = KINDS.fetch(kind)
      flags = kind == NUM || kind == ORD || kind == DECADE ? WORDY : 0
      flags |= ENGLISH if Tables::ENGLISH.include?(word)
      flags |= PLURAL if Tables::PLURAL.include?(word)
      [kind, value, flags, flags & WORDY != 0 && value < 10].freeze
    end

    # A phrase's first word => [[keys of the following words], token entry], longest first
    phrases = Tables::PHRASES.each_with_object({}) do |(text, (kind, value)), h|
      first, *rest = text.split
      (h[pack(first)] ||= []) << [rest.map { pack(_1) }.freeze, entry(text, kind, value)].freeze
    end

    # Key => an entry and then the phrases it begins or nil, so a word needs one lookup; a phrase's first word
    # that is no word alone has a nil kind
    WORDS = Tables::WORDS.to_h { |word, (kind, value)| [pack(word), [*entry(word, kind, value), nil]] }
    phrases.each { |k, list| WORDS[k] = [*(WORDS[k] || [nil, nil, 0, false]).first(4), list.freeze] }
    WORDS.each_value(&:freeze).freeze
    MID = pack("mid")
    ISH = pack("ish")

    # Each byte's class, so the main loop tests one value a byte; the punctuation it keeps is its own byte
    SPACE = 1
    DIGIT = 2
    LETTER = 3
    PUNCT = 4
    CLASS = Array.new(256) do |c|
      if [32, 44, 9, 10, 13].include?(c) then SPACE
      elsif c >= 48 && c <= 57 then DIGIT
      elsif (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || c == 39 || c >= 128 then LETTER
      elsif [46, 45, 47, 43, 64].include?(c) then c
      else PUNCT
      end
    end.freeze
    # A byte's 5-bit code inside a word: either case of a letter alike, the apostrophe 28, a byte of a UTF-8
    # letter 31, which is in no word, other bytes 0. Keys are unique to their text, so a word too long or
    # with such a letter simply matches nothing.
    CODE = Array.new(256) do |c|
      if c >= 97 && c <= 122 then c - 96
      elsif c >= 65 && c <= 90 then c - 64
      elsif c == 39 then 28
      elsif c >= 128 then 31
      else 0
      end
    end.freeze
    # Whether a byte is an ASCII letter, a lookup rather than a call
    ALPHA = Array.new(256) { |c| (c >= 97 && c <= 122) || (c >= 65 && c <= 90) }.freeze
    # An ordinal's suffix ("3rd"), its two bytes lower-cased and packed
    SUFFIX = %w[st nd rd th].to_h { |x| [x.getbyte(0) << 8 | x.getbyte(1), true] }.freeze

    # With an Array for unknown, unknown words and stray punctuation are appended to it as start, stop pairs
    # and lexing carries on; that is how the error path finds them all, and how extraction skips them.
    def self.lex(s, unknown = nil)
      n = s.bytesize
      t = []
      i = 0
      while i < n
        c = s.getbyte(i)
        cl = CLASS[c]
        if cl == SPACE
          i += 1
        elsif cl == LETTER
          # the "T" between an ISO date and its time
          if c | 32 == 116 && i > 0 && i + 1 < n && CLASS[s.getbyte(i - 1)] == DIGIT && CLASS[s.getbyte(i + 1)] == DIGIT
            i += 1
            next
          end
          st = i
          k = 0
          while i < n
            x = CODE[s.getbyte(i)]
            if x == 0
              break unless s.getbyte(i) == 46 && i + 1 < n && (x = CODE[s.getbyte(i + 1)]) >= 1 && x <= 26
              x = 27
            end
            k = k * 32 + x
            i += 1
          end
          word = WORDS[k]
          if word && word[4] && (match = phrase(s, i, n, word[4]))
            i, word = match
          end
          if word && (kind = word[0])
            flags = word[2]
            flags |= CAP if c <= 90 && c >= 65
            value = word[1]
            # "twenty four", "twenty-fourth": one number
            if word[3] && (m = t.size - STRIDE) >= 0 && t[m] == NUM && t[m + 2] & WORDY != 0 && t[m + 1] >= 20 &&
               t[m + 1] % 10 == 0 && only_gap?(s, t[m + 4], st)
              t[m] = kind
              t[m + 1] += value
              t[m + 4] = i
            else
              t.push(kind, value, flags, st, i)
            end
          elsif k == 28 && i < n && CLASS[s.getbyte(i)] == DIGIT
            # an apostrophe for the century left out: "'90s", "'00"
          elsif i - st > 3 && i - st < 13 && k >> 5 * (i - st - 3) == MID && (rest = WORDS[k & (1 << 5 * (i - st - 3)) - 1]) && rest[0]
            # "midweek", "midmorning": "mid" and a word
            t.push(FUZZ, :mid, 0, st, st + 3, rest[0], rest[1], rest[2], st + 3, i)
          elsif i - st > 5 && k & 32_767 == ISH && (stem = WORDS[k >> 15]) && stem[0]
            # "noonish", "tenish": a word of three letters or more, then "ish" as "around" (D14), not "dish"
            t.push(stem[0], stem[1], stem[2], st, i - 3, WORD, :around, 0, i - 3, i)
          else
            return Failure.new(:unknown_word, st, i) unless unknown
            unknown << st << i
          end
        elsif cl == DIGIT
          st = i
          v = 0
          while i < n && CLASS[c = s.getbyte(i)] == DIGIT
            v = v * 10 + c - 48
            i += 1
          end
          nd = i - st
          v /= 10**(nd - 9) if nd > 9 # the first nine digits
          flags = nd > DIGITS ? DIGITS : nd
          flags |= ZERO if nd > 1 && s.getbyte(st) == 48
          if i < n && c == 58
            # the minutes, and below the seconds: two digits, each byte less 48
            unless nd <= 2 && i + 2 < n && CLASS[a = s.getbyte(i + 1)] == DIGIT && CLASS[b = s.getbyte(i + 2)] == DIGIT
              if nd == 4 && i + 6 < n && s.getbyte(i + 3) == 58 && s.getbyte(i + 6) == 58
                # "06/Nov/2023:06:36:02", a log's timestamp: the year, then its time
                t.push(NUM, v, flags, st, i)
                i += 1
                next
              end
              return Failure.new(:invalid_date, st, i + 3 < n ? i + 3 : n) unless unknown
              i = malformed(s, st, i, n, unknown)
              next
            end
            mi = a * 10 + b - 528
            i += 3
            sec = 0
            if i < n && s.getbyte(i) == 58
              unless i + 2 < n && CLASS[a = s.getbyte(i + 1)] == DIGIT && CLASS[b = s.getbyte(i + 2)] == DIGIT
                return Failure.new(:invalid_date, st, i + 3 < n ? i + 3 : n) unless unknown
                i = malformed(s, st, i, n, unknown)
                next
              end
              sec = a * 10 + b - 528
              i += 3
              flags |= SECONDS
              if i + 1 < n && s.getbyte(i) == 46 && CLASS[s.getbyte(i + 1)] == DIGIT # fractions of a second are dropped
                i += 1
                i += 1 while i < n && CLASS[s.getbyte(i)] == DIGIT
              end
            end
            t.push(CLOCK, v * 10_000 + mi * 100 + sec, flags, st, i)
          elsif i + 1 < n && SUFFIX[(c | 32) << 8 | (s.getbyte(i + 1) | 32)] && (i + 2 >= n || !ALPHA[s.getbyte(i + 2)])
            i += 2
            t.push(ORD, v, flags, st, i)
          elsif (c | 32 == 115 || c == 39) && (nd == 2 || nd == 4) && v % 10 == 0 && (j = decade_end(s, i, n))
            # "1990s", "90's"
            i = j
            t.push(DECADE, v, flags, st, i)
          else
            flags |= SHORT if nd == 2 && st > 0 && s.getbyte(st - 1) == 39
            t.push(NUM, v, flags, st, i)
            # "2026-10-23": the hyphens and month of an ISO date at once, as the loop would lex them
            if nd == 4 && c == 45 && i + 4 < n && CLASS[a = s.getbyte(i + 1)] == DIGIT &&
               CLASS[b = s.getbyte(i + 2)] == DIGIT && s.getbyte(i + 3) == 45 && CLASS[s.getbyte(i + 4)] == DIGIT
              t.push(DASH, 0, 0, i, i + 1, NUM, a * 10 + b - 528, a == 48 ? 2 | ZERO : 2, i + 1, i + 3, DASH, 0, 0, i + 3, i + 4)
              i += 4
            end
          end
        else
          case c
          when 46
            t.push(DOT, 0, 0, i, i + 1) if i > 0 && i + 1 < n && CLASS[s.getbyte(i - 1)] == DIGIT && CLASS[s.getbyte(i + 1)] == DIGIT
            i += 1
          when 45
            # A hyphen inside a word ("twenty-four", "mid-october") is a space; after a month or weekday it
            # is a range ("jun-aug", "mon-fri")
            if !(i > 0 && i + 1 < n && ALPHA[s.getbyte(i - 1)] && ALPHA[s.getbyte(i + 1)]) ||
               ((k = t[-5]) == MONTH || k == WDAY) && t[-1] == i
              t.push(DASH, 0, 0, i, i + 1)
            end
            i += 1
          when 47
            t.push(SLASH, 0, 0, i, i + 1)
            i += 1
          when 43
            t.push(PLUS, 0, 0, i, i + 1)
            i += 1
          when 64
            t.push(AT, 0, 0, i, i + 1)
            i += 1
          when 40, 41
            # "9 am (BST)", "-0500 (CDT)": a zone in brackets is the zone
            if c == 40 ? zone_in_brackets?(s, i + 1, n) : t[-5] == ZONE && t[-1] == i && s.getbyte(t[-2] - 1) == 40
              i += 1
              next
            end
            return Failure.new(:unknown_word, i, i + 1) unless unknown
            unknown << i << i + 1
            i += 1
          else
            st = i
            i += 1
            i += 1 while i < n && CLASS[s.getbyte(i)] == PUNCT
            return Failure.new(:unknown_word, st, i) unless unknown
            unknown << st << i
          end
        end
      end
      t
    end

    # Tries each phrase starting with the word just read: [stop, token entry] on a match. Phrases are rare, so
    # this path may rescan and allocate.
    def self.phrase(s, i, n, cands)
      j = i
      j += 1 while j < n && ((c = s.getbyte(j)) == 32 || c == 45 || c == 46)
      return if j == i
      first = 0
      while j < n && (ALPHA[c = s.getbyte(j)] || c == 39)
        first = first * 32 + CODE[c]
        j += 1
      end
      cands.each do |rest, entry|
        next unless rest[0] == first
        j = i
        ok = rest.all? do |want|
          gap = j
          j += 1 while j < n && ((c = s.getbyte(j)) == 32 || c == 45 || c == 46) # "st. patrick's"
          next false if j == gap
          k = 0
          while j < n && (ALPHA[c = s.getbyte(j)] || c == 39)
            k = k * 32 + CODE[c]
            j += 1
          end
          k == want
        end
        return [j, entry] if ok && (j >= n || !ALPHA[s.getbyte(j)])
      end
      nil
    end

    # Where a decade's "s" or "'s" ends, or nil
    def self.decade_end(s, i, n)
      i += 1 if i + 1 < n && s.getbyte(i) == 39
      return unless i < n && s.getbyte(i) | 32 == 115
      i + 1 >= n || !ALPHA[s.getbyte(i + 1)] ? i + 1 : nil
    end

    def self.zone_in_brackets?(s, i, n)
      st = i
      k = 0
      while i < n && (x = CODE[s.getbyte(i)]) != 0
        k = k * 32 + x
        i += 1
      end
      return false unless i > st && (word = WORDS[k])
      if word[4] && (match = phrase(s, i, n, word[4]))
        i, word = match
      end
      i < n && s.getbyte(i) == 41 && word[0] == ZONE
    end

    # A malformed clock ("4:3", "123:00") is one unknown word, to the end of its digits, colons and letters
    def self.malformed(s, st, i, n, unknown)
      i += 1 while i < n && ((c = CLASS[s.getbyte(i)]) == DIGIT || c == LETTER || s.getbyte(i) == 58)
      unknown << st << i
      i
    end

    def self.only_gap?(s, from, to)
      return false if from == to
      while from < to
        c = s.getbyte(from)
        return false unless c == 32 || c == 45
        from += 1
      end
      true
    end

    def self.unknown_ranges(s)
      ranges = []
      lex(s, ranges)
      ranges.each_slice(2).map { |st, stop| st...stop }
    end

    def self.inspect_tokens(t, s)
      t.each_slice(STRIDE).map do |kind, value, flags, st, stop|
        "#{KIND_NAMES[kind]}(#{value}#{flags == 0 ? "" : format(", flags=%#x", flags)}) #{s.byteslice(st, stop - st).inspect}"
      end
    end
  end
end
