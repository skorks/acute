module Acute
  module Resolve
    # Calendar periods and unit arithmetic on local wall seconds
    module Period
      DAY = 86_400
      SECONDS = { second: 1, minute: 60, hour: 3600 }.freeze
      MONTHS = { month: 1, quarter: 3, season: 3, year: 12, decade: 120, century: 1200 }.freeze
      DAYS = { day: 1, week: 7, fortnight: 14 }.freeze

      def self.day(t) = t / DAY

      def self.ymd(t) = Calendar.civil_from_days(t / DAY)

      def self.year(t) = Calendar.year_of(t / DAY)

      def self.civil(y, m, d) = Calendar.days_from_civil(y, m, d) * DAY

      # Months since year 0, so a month is one Integer
      def self.month_index(t)
        p = ymd(t)
        (p / 10_000) * 12 + p / 100 % 100 - 1
      end

      def self.month_start(i) = civil(i / 12, i % 12 + 1, 1)

      # The first day (a day number) of the week holding day d, for a week starting on week_start
      def self.week_first(d, week_start) = d - (Calendar.weekday(d) - week_start) % 7

      # A cycle is how often a periodic phrase repeats: :day, :week, :month or :year. Index i counts cycles.
      def self.index(cycle, ctx, t)
        case cycle
        when :day then day(t)
        when :week then (day(t) - ctx.week_start + 4) / 7
        when :month then month_index(t)
        else Calendar.year_of(t / DAY)
        end
      end

      def self.span(cycle, ctx, i)
        case cycle
        when :day then Span.new(i * DAY, (i + 1) * DAY, :day, nil)
        when :week
          b = (i * 7 + ctx.week_start - 4) * DAY
          Span.new(b, b + 7 * DAY, :week, nil)
        when :month then Span.new(month_start(i), month_start(i + 1), :month, nil)
        else
          y = i - 1 # Calendar.year_start, inline
          b = 365 * y + y / 4 - y / 100 + y / 400 - 719_162
          Span.new(b * DAY, (b + (i % 4 == 0 && (i % 100 != 0 || i % 400 == 0) ? 366 : 365)) * DAY, :year, nil)
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
          i -= unit == :season ? (i + 1) % 3 : i % n # D33: seasons start in December, March, June and September
          Span.new(month_start(i), month_start(i + n), unit, nil)
        end
      end

      # t moved by n units (D23: Temporal arithmetic, so jan 31 + 1 month is feb 28). ctx only for business days.
      def self.add(t, n, unit, ctx = nil)
        if (s = SECONDS[unit]) then t + n * s
        elsif (d = DAYS[unit]) then t + n * d * DAY
        elsif unit == :business_day then business(t, n, ctx)
        else
          p = ymd(t)
          y = p / 10_000
          m = p / 100 % 100
          i = y * 12 + m - 1 + n * MONTHS[unit]
          y = i / 12
          m = i % 12 + 1
          d = p % 100
          last = Calendar.days_in_month(y, m)
          civil(y, m, d < last ? d : last) + t % DAY
        end
      end

      LIMIT = 10_000
      class Limit < StandardError; end

      # D49: what one call may still count, shared by every count in it (T17): LIMIT business days in all, and
      # LIMIT days a business_days: calendar says aren't. It holds the calendar too, so a holidays-gem year is
      # looked up once a call.
      class Budget
        attr_accessor :days, :skips, :workdays

        def initialize
          @days = @skips = LIMIT
        end
      end

      # D17: Monday to Friday, or D47: the days business_days: or holidays: give; D38: the time of day is kept.
      # D49: past the call's Budget is a failure.
      def self.business(t, n, ctx)
        return t if n == 0
        budget = ctx.budget
        raise Limit if n.abs > budget.days
        budget.days -= n.abs
        d = t / DAY
        days = ctx.business_days
        to = case days
             when nil then Calendar.add_weekdays(d, n)
             when Holidays::RegionDays then days.add(d, n)
             else step(d, n, days, budget)
             end
        t + (to - d) * DAY
      end

      # A business_days: calendar, or holidays: that only answer holiday?, are asked day by day
      def self.step(d, n, days, budget)
        step = n < 0 ? -1 : 1
        n.abs.times do
          d += step
          until days.business_day?(::Date.jd(d + 2_440_588))
            raise Limit if (budget.skips -= 1) < 0
            d += step
          end
        end
        d
      end

      # D40: "half a year" is 6 months; a fraction becomes a whole count of the next smaller unit
      SMALLER = Ractor.make_shareable({ year: [:month, 12], quarter: [:month, 3], season: [:month, 3], month: [:day, 30], fortnight: [:day, 14],
                                        week: [:day, 7], day: [:hour, 24], hour: [:minute, 60], minute: [:second, 60] })

      def self.whole(count, unit)
        while count.is_a?(Rational) && count.denominator != 1 && (smaller = SMALLER[unit])
          unit, k = smaller
          count *= k
        end
        [count.to_i, unit]
      end

      # D17, D38: only with fiscal_year_start:, and FY27 is the year ending in 2027; "next fiscal year" is the
      # one after the fiscal year holding today
      def self.fiscal(node, ctx, shift = nil)
        start = ctx.fiscal_year_start
        return [] unless start
        if shift
          ym = ymd(ctx.now_local) / 100
          y = ym / 100 + shift - (ym % 100 < start ? 1 : 0)
        else
          y = start == 1 ? node.year : node.year - 1
        end
        Span.new(civil(y, start, 1), civil(y + 1, start, 1), :year, nil).then { [_1] }
      end
    end
  end
end
