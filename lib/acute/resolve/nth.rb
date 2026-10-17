module Acute
  module Resolve
    module Periodic
      # "second tuesday of march", "last friday of the month", "Q3", "first day of next month"
      def self.nth(node, s, ctx)
        n = node.n
        x = node.node
        out = case x
              when G::Weekday
                # the nth wday from the first day, or the last one back from the last day; (d + 4) % 7 is d's weekday
                if n > 0
                  d = s.b / DAY
                  d += (x.wday - (d + 4) % 7) % 7 + 7 * (n - 1)
                else
                  d = s.e / DAY - 1
                  d -= (d + 4 - x.wday) % 7
                end
                b = d * DAY
                return b >= s.b && b + DAY <= s.e ? [Span.new(b, b + DAY, :day, nil)] : []
              when G::Weekend
                if n > 0
                  sat = Named.nth_weekday(Period.day(s.b), 6, n)
                else
                  sat = s.e / DAY - 1
                  sat -= (sat - 2) % 7 # (sat + 4 - 6) % 7: days back to a Saturday
                end
                # D44: the weekend whose Saturday is in the period, though it ends after it
                return [] unless sat * DAY >= s.b && sat * DAY < s.e
                return Named.weekends(Period.span(:week, ctx, Period.index(:week, ctx, sat * DAY)), ctx)
              else
                unit = x.unit
                if unit == :business_day # D44: the nth weekday, or the last
                  b = n > 0 ? Period.business(s.b - DAY, n) : Period.business(s.e, -1)
                  [Span.new(b, b + DAY, :day, nil)]
                elsif Period::DAYS[unit]
                  b = n > 0 ? s.b + (n - 1) * Period::DAYS[unit] * DAY : s.e - Period::DAYS[unit] * DAY
                  [Span.new(b, b + Period::DAYS[unit] * DAY, unit, nil)]
                else
                  b = n > 0 ? Period.add(s.b, n - 1, unit) : Period.add(s.e, -1, unit)
                  [Span.new(b, Period.add(b, 1, unit), unit, nil)]
                end
              end
        out.select { |o| o.b >= s.b && o.e <= s.e }
      end
    end
  end
end
