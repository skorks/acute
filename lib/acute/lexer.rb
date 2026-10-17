require_relative "errors"
require_relative "tables/words"

module Acute
  # Bytes to tokens. The result is one flat Integer Array, STRIDE entries per token:
  # kind, value, flags, start, stop (byte offsets, stop exclusive). Failures come back as a Failure value.
  module Lexer
    STRIDE = 5

    NUM = 0     # value: the number; flags: digit count, ZERO
    CLOCK = 1   # value: hhmmss as decimal digits; flags: hour digit count, ZERO, SECONDS
    MER = 2     # value: 0 for am, 12 for pm
    DAY = 3     # value: days from today
    NAMED = 4   # value: the hour named (noon 12, midnight 0)
    NOW = 5
    AT = 6
    KIND_NAMES = %w[NUM CLOCK MER DAY NAMED NOW AT].freeze

    DIGITS = 15
    ZERO = 16
    SECONDS = 32
    MAX_WORD = 12

    KINDS = { day: DAY, meridiem: MER, named: NAMED, now: NOW, at: AT }.freeze

    # A word packs into an Integer, 5 bits a character, so lookup needs no substring
    def self.pack(word) = word.each_byte.reduce(0) { |k, c| k * 32 + code(c) }

    def self.code(c)
      if c >= 97 then c - 96
      elsif c == 46 then 27
      else 28
      end
    end

    WORDS = Tables::WORDS.to_h { |word, (kind, value)| [pack(word), [KINDS.fetch(kind), value].freeze] }.freeze

    # With an Array for unknown, unknown words and stray punctuation are appended to it as start, stop pairs
    # and lexing carries on; that is the error path's way of finding them all.
    def self.lex(s, unknown = nil)
      n = s.bytesize
      t = []
      i = 0
      while i < n
        c = s.getbyte(i)
        if c == 32 || c == 44 || c == 46 || c == 9 || c == 10 || c == 13
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
            end
            t << CLOCK << v * 10_000 + mi * 100 + sec << flags << st << i
          else
            t << NUM << v << flags << st << i
          end
        elsif c == 64
          t << AT << 0 << 0 << i << i + 1
          i += 1
        elsif (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || c == 39 || c >= 128
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
          if plain && len <= MAX_WORD && (word = WORDS[k])
            t << word[0] << word[1] << 0 << st << i
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

    # 0-99, or -1 unless both bytes are digits
    def self.two_digits(s, i, n)
      return -1 if i + 1 >= n
      a = s.getbyte(i) - 48
      b = s.getbyte(i + 1) - 48
      a >= 0 && a <= 9 && b >= 0 && b <= 9 ? a * 10 + b : -1
    end

    def self.punctuation?(c)
      !(c == 32 || c == 44 || c == 46 || c == 9 || c == 10 || c == 13 || c == 64 || (c >= 48 && c <= 57) ||
        (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || c == 39 || c >= 128)
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
