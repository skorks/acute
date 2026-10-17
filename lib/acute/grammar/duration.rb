module Acute
  # Lengths of time: counted units only, so "next friday" is not one
  class Grammar
    def self.duration(tokens) = new(tokens).duration

    # "3 days", "1h 30m", "2 weeks and 3 days", "an hour and a half", "half an hour": the Units said
    def duration
      parts = []
      while @i < @n
        @i += S if parts.any? && (@t[@i + 1] == :and || @t[@i] == L::PLUS)
        if parts.any? && @t[@i] == L::ART && @t[@i + S + 1] == :half && @t[@i + 2 * S] != L::UNIT
          @i += 2 * S
          parts << Unit.new(parts.last.unit, Rational(1, 2))
          next
        end
        half = @t[@i + 1] == :half
        @i += S if half
        q = quantity
        return failure(@i < @n ? :conflict : :incomplete) unless q && q.count.positive?
        q.count = Rational(q.count, 2) if half
        parts << q
      end
      parts.empty? ? failure(:incomplete) : parts
    end
  end
end
