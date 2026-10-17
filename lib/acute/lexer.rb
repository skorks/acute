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
    KIND_NAMES = %w[NUM CLOCK MER DAY NAMED NOW AT WDAY MONTH UNIT REL ORD PART SEASON HOLIDAY WEEKEND ZONE FUZZ ART
                    WORD SLASH DASH DOT PLUS].freeze

    DIGITS = 15
    ZERO = 16
    SECONDS = 32
    WORDY = 64     # a number or ordinal written as a word
    ENGLISH = 128  # also an ordinary English word ("may", "sat", "second"), for extraction
    CAP = 256      # written with a capital
    MAX_WORD = 12

    KINDS = {
      day: DAY, meridiem: MER, named: NAMED, now: NOW, at: AT, weekday: WDAY, month: MONTH, unit: UNIT,
      relative: REL, number: NUM, ordinal: ORD, part: PART, season: SEASON, holiday: HOLIDAY, weekend: WEEKEND,
      zone: ZONE, fuzzy: FUZZ, article: ART, word: WORD
    }.freeze

    # A word packs into an Integer, 5 bits a character, so lookup needs no substring
    def self.pack(word) = word.each_byte.reduce(0) { |k, c| k * 32 + code(c) }

    def self.code(c)
      if c >= 97 then c - 96
      elsif c == 46 then 27
      else 28
      end
    end

    def self.entry(word, kind, value)
      kind = KINDS.fetch(kind)
      flags = kind == NUM || kind == ORD ? WORDY : 0
      flags |= ENGLISH if Tables::ENGLISH.include?(word)
      [kind, value, flags].freeze
    end

    WORDS = Tables::WORDS.to_h { |word, (kind, value)| [pack(word), entry(word, kind, value)] }.freeze

    # First word's key => [[keys of the following words], token entry], longest first
    PHRASES = Tables::PHRASES.each_with_object({}) do |(text, (kind, value)), h|
      first, *rest = text.split
      (h[pack(first)] ||= []) << [rest.map { pack(_1) }.freeze, entry(text, kind, value)].freeze
    end.freeze

    # With an Array for unknown, unknown words and stray punctuation are appended to it as start, stop pairs
    # and lexing carries on; that is how the error path finds them all, and how extraction skips them.
    def self.lex(s, unknown = nil)
      n = s.bytesize
      t = []
      i = 0
      while i < n
        c = s.getbyte(i)
        if c == 32 || c == 44 || c == 9 || c == 10 || c == 13
          i += 1
        elsif c >= 48 && c <= 57
          st = i
          v = 0
          while i < n && (c = s.getbyte(i)) >= 48 && c <= 57
            v = v * 10 + c - 48 if i - st < 9
            i += 1
          end
          nd = i - st
          flags = nd > DIGITS ? DIGITS : nd
          flags |= ZERO if nd > 1 && s.getbyte(st) == 48
          if i < n && c == 58
            mi = two_digits(s, i + 1, n)
            return Failure.new(:invalid_date, st, i + 3 < n ? i + 3 : n) if mi < 0 || nd > 2
            i += 3
            sec = 0
            if i < n && s.getbyte(i) == 58
              sec = two_digits(s, i + 1, n)
              return Failure.new(:invalid_date, st, i + 3 < n ? i + 3 : n) if sec < 0
              i += 3
              flags |= SECONDS
              if i + 1 < n && s.getbyte(i) == 46 && digit?(s.getbyte(i + 1)) # fractions of a second are dropped
                i += 1
                i += 1 while i < n && digit?(s.getbyte(i))
              end
            end
            t << CLOCK << v * 10_000 + mi * 100 + sec << flags << st << i
          elsif ordinal_suffix?(s, i, n)
            i += 2
            t << ORD << v << flags << st << i
          else
            t << NUM << v << flags << st << i
          end
        elsif c == 46
          t << DOT << 0 << 0 << i << i + 1 if i > 0 && i + 1 < n && digit?(s.getbyte(i - 1)) && digit?(s.getbyte(i + 1))
          i += 1
        elsif c == 45
          # A hyphen inside a word ("twenty-four", "mid-october") is a space
          unless i > 0 && i + 1 < n && letter?(s.getbyte(i - 1)) && letter?(s.getbyte(i + 1))
            t << DASH << 0 << 0 << i << i + 1
          end
          i += 1
        elsif c == 47 || c == 43 || c == 64
          t << (c == 47 ? SLASH : c == 43 ? PLUS : AT) << 0 << 0 << i << i + 1
          i += 1
        elsif letter?(c) || c == 39 || c >= 128
          st = i
          k = 0
          len = 0
          plain = true
          while i < n
            c = s.getbyte(i)
            if c >= 97 && c <= 122 then x = c - 96
            elsif c >= 65 && c <= 90 then x = c - 64
            elsif c == 39 then x = 28
            elsif c == 46 && i + 1 < n && ((c2 = s.getbyte(i + 1) | 32) >= 97 && c2 <= 122) then x = 27
            elsif c >= 128
              plain = false
              x = 0
            else break
            end
            k = k * 32 + x if len < MAX_WORD
            len += 1
            i += 1
          end
          word = nil
          if plain && len <= MAX_WORD
            if (cands = PHRASES[k]) && (match = phrase(s, i, n, cands))
              i, word = match
            else
              word = WORDS[k]
            end
          end
          if word
            flags = word[2]
            flags |= CAP if (b = s.getbyte(st)) >= 65 && b <= 90
            kind = word[0]
            value = word[1]
            m = t.size - STRIDE
            # "twenty four", "twenty-fourth": one number
            if (kind == NUM || kind == ORD) && flags & WORDY != 0 && value < 10 && m >= 0 && t[m] == NUM &&
               t[m + 2] & WORDY != 0 && t[m + 1] >= 20 && t[m + 1] % 10 == 0 && only_gap?(s, t[m + 4], st)
              t[m] = kind
              t[m + 1] += value
              t[m + 4] = i
            else
              t << kind << value << flags << st << i
            end
          else
            return Failure.new(:unknown_word, st, i) unless unknown
            unknown << st << i
          end
        else
          st = i
          i += 1
          i += 1 while i < n && punctuation?(s.getbyte(i))
          return Failure.new(:unknown_word, st, i) unless unknown
          unknown << st << i
        end
      end
      t
    end

    # Tries each phrase starting with the word just read: [stop, token entry] on a match. Phrases are rare, so
    # this path may rescan and allocate.
    def self.phrase(s, i, n, cands)
      cands.each do |rest, entry|
        j = i
        ok = rest.all? do |want|
          gap = j
          j += 1 while j < n && ((c = s.getbyte(j)) == 32 || c == 45)
          next false if j == gap
          k = 0
          len = 0
          while j < n && (letter?(c = s.getbyte(j)) || c == 39)
            k = k * 32 + (c == 39 ? 28 : (c | 32) - 96) if len < MAX_WORD
            len += 1
            j += 1
          end
          k == want && len <= MAX_WORD
        end
        return [j, entry] if ok && (j >= n || !letter?(s.getbyte(j)))
      end
      nil
    end

    def self.ordinal_suffix?(s, i, n)
      return false if i + 1 >= n
      a = s.getbyte(i) | 32
      b = s.getbyte(i + 1) | 32
      ((a == 115 && b == 116) || (a == 110 && b == 100) || (a == 114 && b == 100) || (a == 116 && b == 104)) &&
        (i + 2 >= n || !letter?(s.getbyte(i + 2)))
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

    def self.letter?(c) = (c >= 97 && c <= 122) || (c >= 65 && c <= 90)

    def self.digit?(c) = c >= 48 && c <= 57

    # 0-99, or -1 unless both bytes are digits
    def self.two_digits(s, i, n)
      return -1 if i + 1 >= n
      a = s.getbyte(i) - 48
      b = s.getbyte(i + 1) - 48
      a >= 0 && a <= 9 && b >= 0 && b <= 9 ? a * 10 + b : -1
    end

    def self.punctuation?(c)
      !(c == 32 || c == 44 || c == 46 || c == 45 || c == 47 || c == 43 || c == 9 || c == 10 || c == 13 ||
        c == 64 || digit?(c) || letter?(c) || c == 39 || c >= 128)
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
