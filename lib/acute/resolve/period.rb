module Acute
  module Resolve
    # Calendar periods and unit arithmetic on local wall seconds
    module Period
      DAY = 86_400
      SECONDS = { second: 1, minute: 60, hour: 3600 }.freeze
      MONTHS = { month: 1, quarter: 3, year: 12, decade: 120, century: 1200 }.freeze
      DAYS = { day: 1, week: 7, fortnight: 14 }.freeze

      def self.day(t) = t.div(DAY)

      def self.ymd(t) = Calendar.civil_from_days(t.div(DAY))

      def self.civil(y, m, d) = Calendar.days_from_civil(y, m, d) * DAY

      # Months since year 0, so a month is one Integer
      def self.month_index(t)
        p = ymd(t)
        (p / 10_000) * 12 + p / 100 % 100 - 1
      end

      def self.month_start(i) = civil(i.div(12), i % 12 + 1, 1)

      # The first day (a day number) of the week holding day d, for a week starting on week_start
      def self.week_first(d, week_start) = d - (Calendar.weekday(d) - week_start) % 7

      # A cycle is how often a periodic phrase repeats: :day, :week, :month or :year. Index i counts cycles.
      def self.index(cycle, ctx, t)
        case cycle
        when :day then day(t)
        when :week then (day(t) - ctx.week_start + 4).div(7)
        when :month then month_index(t)
        else ymd(t) / 10_000
        end
      end

      def self.span(cycle, ctx, i)
        case cycle
        when :day then Span.new(i * DAY, (i + 1) * DAY, :day, nil)
        when :week
          b = (i * 7 + ctx.week_start - 4) * DAY
          Span.new(b, b + 7 * DAY, :week, nil)
        when :month then Span.new(month_start(i), month_start(i + 1), :month, nil)
        else Span.new(civil(i, 1, 1), civil(i + 1, 1, 1), :year, nil)
        end
      end

      # The calendar unit holding t
      def self.unit(unit, ctx, t)
        case unit
        when :second, :minute, :hour
          len = SECONDS[unit]
          b = t - t % len
          Span.new(b, b + len, unit, nil)
        when :day, :business_day then span(:day, ctx, day(t))
        when :week, :fortnight then span(:week, ctx, index(:week, ctx, t))
        when :month then span(:month, ctx, month_index(t))
        else
          n = MONTHS[unit]
          i = month_index(t)
          i -= i % n
          Span.new(month_start(i), month_start(i + n), unit, nil)
        end
      end

      # t moved by n units (D23: Temporal arithmetic, so jan 31 + 1 month is feb 28)
      def self.add(t, n, unit)
        if (s = SECONDS[unit]) then t + n * s
        elsif (d = DAYS[unit]) then t + n * d * DAY
        elsif unit == :business_day then business(t, n)
        else
          p = ymd(t)
          y = p / 10_000
          m = p / 100 % 100
          i = y * 12 + m - 1 + n * MONTHS[unit]
          y = i.div(12)
          m = i % 12 + 1
          d = [p % 100, Calendar.days_in_month(y, m)].min
          civil(y, m, d) + t % DAY
        end
      end

      # D17: Monday to Friday; D38: the time of day is kept
      def self.business(t, n)
        step = n < 0 ? -1 : 1
        n.abs.times do
          t += step * DAY
          t += step * DAY while Calendar.weekday(day(t)) % 6 == 0
        end
        t
      end

      # D40: "half a year" is 6 months; a fraction becomes a whole count of the next smaller unit
      SMALLER = { year: [:month, 12], quarter: [:month, 3], month: [:day, 30], fortnight: [:day, 14],
                  week: [:day, 7], day: [:hour, 24], hour: [:minute, 60], minute: [:second, 60] }.freeze

      def self.whole(count, unit)
        while count.is_a?(Rational) && count.denominator != 1 && (smaller = SMALLER[unit])
          unit, k = smaller
          count *= k
        end
        [count.to_i, unit]
      end

      # D17, D38: only with fiscal_year_start:, and FY27 is the year ending in 2027
      def self.fiscal(node, ctx)
        start = ctx.fiscal_year_start
        return [] unless start
        y = start == 1 ? node.year : node.year - 1
        Span.new(civil(y, start, 1), civil(y + 1, start, 1), :year, nil).then { [_1] }
      end
    end
  end
end
