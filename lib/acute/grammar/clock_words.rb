module Acute
  # Clocks said in words: "twenty past four", "a quarter to six", "10 after 2", "20 minutes past 3pm"
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
      return failure(:incomplete) unless clock_word?(@i)
      to = @t[@i + 1] == :to || @t[@i + 1] == :before
      @i += S
      if @t[@i] == L::NAMED
        noon = @t[@i + 1] == 12
        @i += S
        return Clock.new(11, 60 - minutes, 0, noon ? :am : :pm, nil, false, false) if to
        return Clock.new(12, minutes, 0, noon ? :pm : :am, nil, false, false)
      end
      return failure(:incomplete) unless @t[@i] == L::NUM && @t[@i + 1].between?(1, 12)
      hour = @t[@i + 1]
      @i += S
      @i += S if @t[@i] == L::WORD && @t[@i + 1] == :oclock
      meridiem = nil
      if @t[@i] == L::MER
        meridiem = @t[@i + 1] == 0 ? :am : :pm
        @i += S
      end
      return Clock.new(hour == 1 ? 12 : hour - 1, 60 - minutes, 0, meridiem, nil, false, false) if to
      Clock.new(hour, minutes, 0, meridiem, nil, false, false)
    end
  end
end
