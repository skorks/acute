require_relative "lexer"
require_relative "grammar"

module Acute
  # Number words, ordinals and fractions in a text as digits, read from acute's tokens; every other byte is kept
  # (D46). The numerizer layer's answer, and chronic_duration's number words.
  # @api private
  module Numerize
    L = Lexer
    S = L::STRIDE
    BIG = Grammar::MULTIPLIERS

    def self.call(s)
      t = L.lex(s, [])
      n = t.size
      out = nil
      copied = 0
      i = 0
      while i < n
        if (read = number(s, t, i, n))
          i, stop, digits = read
          (out ||= +"") << s.byteslice(copied, t[read[3] + 3] - copied) << digits
          copied = stop
        else
          i += S
        end
      end
      return s.dup unless out
      out << s.byteslice(copied, s.bytesize - copied)
    end

    # The number at token i: [the token after it, its stop, its digits, i], or nil
    def self.number(s, t, i, n)
      k = t[i]
      if k == L::ART
        d = denominator(s, t, i + S, n)
        return [d[1], d[2], "1/#{d[0]}", i] if d
      elsif k == L::ORD
        return unless wordy?(t, i) && t[i + 1] > 0 && t[i + 2] & L::ENGLISH == 0
        return [i + S, t[i + 4], ordinal(t[i + 1]), i]
      elsif k == L::WORD && t[i + 1] == :oh && t[i + 4] - t[i + 3] == 4
        return [i + S, t[i + 4], "0", i] # "zero", which acute reads as the "oh" of "twelve oh three"
      end
      return unless (said = cardinal(s, t, i, n))
      value, j, big, ord = said
      return [j, t[j - S + 4], ordinal(value), i] if ord
      if !big && (wordy?(t, i) || t[i + 1] < 100) && (d = denominator(s, t, j, n))
        return [d[1], d[2], "#{value}/#{d[0]}", i]
      elsif j < n && joined?(s, t, j) && (f = mixed(s, t, j, n))
        return [f[1], f[2], (value + f[0].to_f).to_s, i]
      end
      return if !big && t[i + 2] & L::WORDY == 0
      [j, t[j - S + 4], value.to_s, i]
    end

    # A count said in words, or digits before "hundred": [value, the token after it, whether it has a hundred or
    # more, whether it ends in an ordinal]
    def self.cardinal(s, t, i, n)
      k = t[i]
      if k == L::NUM
        group = t[i + 2] & L::WORDY == 0 ? s.byteslice(t[i + 3], t[i + 4] - t[i + 3]).to_i : t[i + 1]
        j = i + S
      elsif (k == L::ART || k == L::WORD) && big(t, k == L::ART ? i + S : i)
        group = 1
        j = k == L::ART ? i + S : i
      else
        return
      end
      total = 0
      hundred = false
      below = nil
      big = false
      after = false # straight after a hundred, a thousand or their "and"
      while j < n && (j == i || joined?(s, t, j))
        k = t[j]
        if (m = big(t, j))
          if m == 100
            break if hundred || group < 1 || group > 99
            group *= 100
            hundred = true
          else
            break if group < 1 || (below && m >= below)
            total += group * m
            group = 0
            hundred = false
            below = m
          end
          big = after = true
          j += S
          return [total + group, j, true, true] if k == L::ORD
        elsif after && k == L::WORD && t[j + 1] == :and && t[j - S + 1] != :and && part?(t, j + S)
          j += S
        elsif after && part?(t, j) && group % 100 == 0 && t[j + 1].between?(1, 99)
          group += t[j + 1]
          after = false
          j += S
          return [total + group, j, true, true] if k == L::ORD
        else
          break
        end
      end
      [total + group, j, big, false]
    end

    # What follows a hundred or a thousand: a number or ordinal in words, or digits before another ("10 thousand
    # and 5 hundred")
    def self.part?(t, j)
      k = t[j]
      (k == L::NUM || k == L::ORD) && (wordy?(t, j) || (k == L::NUM && big(t, j + S)))
    end

    # "hundred", "thousand", or "hundredth" at j: its value
    def self.big(t, j)
      k = t[j]
      if k == L::WORD then BIG[t[j + 1]]
      elsif k == L::ORD && wordy?(t, j) && t[j + 1] >= 100 then t[j + 1]
      end
    end

    # "half", "quarter", "third" to "ninth", or "eighths", after token j - S: [the denominator, the token after
    # it, its stop]
    def self.denominator(s, t, j, n)
      if j < n && joined?(s, t, j)
        k = t[j]
        d = if k == L::WORD && t[j + 1] == :half && ALPHA[s.getbyte(t[j + 3])] then 2
            elsif k == L::UNIT && t[j + 1] == :quarter then 4
            elsif k == L::ORD && wordy?(t, j) && t[j + 1].between?(3, 9) then t[j + 1]
            end
        return [d, j + S, t[j + 4]] if d
      end
      # "eighths": no word of acute's, so no token; the ordinal's own word and an "s"
      i = t[j - S + 4]
      stop = j < n ? t[j + 3] : s.bytesize
      i += 1 while i < stop && ((c = s.getbyte(i)) == 32 || c == 45)
      return if i == t[j - S + 4]
      k = 0
      st = i
      while i < stop && ALPHA[c = s.getbyte(i)]
        k = k * 32 + L::CODE[c]
        i += 1
      end
      return unless i - st > 4 && k & 31 == 19 && (i == stop || L::CLASS[s.getbyte(i)] != L::LETTER) &&
                    (word = L::WORDS[k >> 5]) && word[0] == L::ORD && word[1].between?(3, 9)
      [word[1], j, i]
    end

    # After a whole number: "and a half", "and three quarters", "1/2": [the fraction, the token after it, its stop]
    def self.mixed(s, t, j, n)
      if t[j] == L::WORD && t[j + 1] == :and
        j += S
        return unless j < n && joined?(s, t, j)
        if t[j] == L::ART || (t[j] == L::NUM && t[j + 2] & L::WORDY != 0)
          num = t[j] == L::ART ? 1 : t[j + 1]
          if (d = denominator(s, t, j + S, n))
            return [Rational(num, d[0]), d[1], d[2]]
          end
        end
      elsif t[j] == L::DASH
        j += S
      end
      return unless j + 2 * S < n && t[j] == L::NUM && t[j + S] == L::SLASH && t[j + 2 * S] == L::NUM &&
                    t[j + 2] & L::WORDY == 0 && t[j + 2 * S + 2] & L::WORDY == 0 && t[j + 2 * S + 1] > 0 &&
                    t[j + 4] == t[j + S + 3] && t[j + S + 4] == t[j + 2 * S + 3] && (j + 3 * S >= n || t[j + 3 * S] != L::SLASH)
      [Rational(t[j + 1], t[j + 2 * S + 1]), j + 3 * S, t[j + 2 * S + 4]]
    end

    def self.ordinal(v)
      suffix = if (v % 100).between?(11, 13) then "th"
               elsif v % 10 == 1 then "st"
               elsif v % 10 == 2 then "nd"
               elsif v % 10 == 3 then "rd"
               else "th"
               end
      "#{v}#{suffix}"
    end

    def self.wordy?(t, j) = t[j + 2] & L::WORDY != 0

    # Only spaces and hyphens, or nothing, between token j and the one before
    def self.joined?(s, t, j)
      from = t[j - S + 4]
      to = t[j + 3]
      while from < to
        c = s.getbyte(from)
        return false unless c == 32 || c == 45
        from += 1
      end
      true
    end

    ALPHA = L::ALPHA
  end
end
