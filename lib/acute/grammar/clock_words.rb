module Acute
  # Clocks and years said in words: "twenty past four", "a quarter to six", "four twenty-three", "two thousand"
  class Grammar
    private

    # D42: "five to 9" is 8:55 when the minutes are a word; "5 to 9" and "from five to nine" are ranges.
    # D44: "10 after 2", "twenty before noon" are clocks however the minutes are written.
    def minutes_to?(i)
      w = @t[i + S + 1]
      return hour?(i + 2 * S) && @t[i + 1].between?(1, 59) if w == :after || w == :before
      n = @t[i + 1]
      w == :to && n.between?(1, 30) && hour?(i + 2 * S) &&
        !(i >= S && @t[i - S] == L::WORD && (@t[i - S + 1] == :from || @t[i - S + 1] == :between)) &&
        # D44: "15 to noon" is 11:45, since as a range of hours it would end before it began
        (@t[i + 2] & L::WORDY != 0 || (@t[i + 2 * S] == L::NAMED && @t[i + 2 * S + 1] == 12 && (n <= 5 || n >= 12)))
    end

    # A number word at i and the words after it that say one clock or year with it, or nil
    def said(v, i)
      t = @t
      w = t[i + S + 1]
      if t[i + S] == L::NUM && t[i + S + 2] & L::WORDY != 0
        # "four twenty-three"
        if v.between?(1, 12) && w.between?(10, 59)
          @i += 2 * S
          return said_clock(v, w)
        end
        # D44: "nineteen ninety five", "twenty ten": a year written as two numbers; "fourteen thirty" may be a
        # clock, so from 13 to 23 the second must be past any minute
        if v.between?(13, 29) && w.between?(10, 99) && (v.between?(18, 20) || v > 23 || w > 59)
          @i += 2 * S
          return Date.new(v * 100 + w, nil, nil, nil, false)
        end
      elsif w == :oh # D44: "twelve oh three", "nine zero five"
        if v.between?(1, 12) && t[i + 2 * S] == L::NUM && t[i + 2 * S + 2] & L::WORDY != 0 && (m = t[i + 2 * S + 1]).between?(1, 9)
          @i += 3 * S
          return said_clock(v, m)
        end
      elsif w == :thousand && v.between?(1, 2)
        thousands(v, i)
      end
    end

    def said_clock(h, m)
      c = Clock.new(h, m, 0, nil, nil, false, false)
      if @t[@i] == L::MER
        c.meridiem = @t[@i + 1] == 0 ? :am : :pm
        @i += S
      end
      c
    end

    # D44: "two thousand", "two thousand and eighteen", "two thousand ten": a year in words
    def thousands(v, i)
      j = i + 2 * S
      j += S if @t[j] == L::WORD && @t[j + 1] == :and && @t[j + S] == L::NUM
      year = v * 1000
      if @t[j] == L::NUM && @t[j + 2] & L::WORDY != 0 && @t[j + 1] < 100
        year += @t[j + 1]
        j += S
      end
      @i = j
      Date.new(year, nil, nil, nil, false)
    end

    def hour?(i) = (@t[i] == L::NUM && @t[i + 1].between?(1, 12)) || @t[i] == L::NAMED

    def clock_word?(i)
      k = @t[i]
      v = @t[i + 1]
      (k == L::REL && v == :past) || (k == L::WORD && (v == :to || v == :after || v == :before))
    end

    # "twenty past four", "half past twelve", "a quarter to six", D44: "twenty after 3pm", "10 before 2",
    # "a quarter past noon"
    def clock_words(minutes)
      @i += S
      @i += S if @t[@i - S] == L::ART
      @i += S if @t[@i] == L::UNIT && (@t[@i + 1] == :quarter || @t[@i + 1] == :minute)
      # D48: "half three" is 3:30, as said in Britain
      half = minutes == 30 && @t[@i - S + 1] == :half && @t[@i] == L::NUM
      return failure(:incomplete) unless half || clock_word?(@i)
      to = !half && (@t[@i + 1] == :to || @t[@i + 1] == :before)
      @i += S unless half
      if @t[@i] == L::NAMED
        noon = @t[@i + 1] == 12
        @i += S
        return Clock.new(11, 60 - minutes, 0, noon ? :am : :pm, nil, false, false) if to
        return Clock.new(12, minutes, 0, noon ? :pm : :am, nil, false, false)
      end
      return failure(:incomplete) unless @t[@i] == L::NUM && @t[@i + 1].between?(1, 12)
      hour = @t[@i + 1]
      @i += S
      min = 0
      if @t[@i] == L::NUM && @t[@i + 2] & L::WORDY != 0 && @t[@i + 1].between?(10, 59) # D48: "three mins to five thirty"
        min = @t[@i + 1]
        @i += S
      end
      @i += S if @t[@i] == L::WORD && @t[@i + 1] == :oclock
      meridiem = nil
      if @t[@i] == L::MER
        meridiem = @t[@i + 1] == 0 ? :am : :pm
        @i += S
      end
      t = (hour % 12 * 60 + min + (to ? -minutes : minutes)) % 720
      Clock.new(t < 60 ? 12 : t / 60, t % 60, 0, meridiem, nil, false, false)
    end
  end
end
