module Acute
  module Resolve
    # Calendar dates: "2026-10-23", "oct 23", "10/23", "23.10.2026", "2015"
    module Dates
      ORDER = Assumption.for(:numeric_date_order)
      CENTURY = Assumption.for(:century_from_00)
      DECADE_CENTURY = Assumption.for(:decade_or_century)
      DAY = Period::DAY
      LONGEST = [0, 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31].freeze

      def self.spans(d, ctx)
        if d.sep
          out = []
          orders(d, ctx).each { |x| out.concat(spans(x, ctx)) }
          return out
        end
        return Periodic.bare(d, ctx) unless d.year
        y = d.short ? two_digit_year(d.year, ctx) : d.year
        return [] if y < 1 # D18
        m = d.month
        if (day = d.day)
          return [] unless m >= 1 && m <= 12 && day >= 1 && (day <= 28 || day <= Calendar.days_in_month(y, m))
          b = Calendar.days_from_civil(y, m, day) * DAY
          [Span.new(b, b + DAY, :day, nil)]
        elsif m
          return [] unless m >= 1 && m <= 12
          b = Calendar.days_from_civil(y, m, 1) * DAY
          [Span.new(b, b + (m == 2 ? Calendar.days_in_month(y, m) : Calendar::MONTH_DAYS[m]) * DAY, :month, nil)]
        else
          [Span.new(Calendar.year_start(y) * DAY, Calendar.year_start(y + 1) * DAY, :year, nil)]
        end
      end

      # D12: "the 15th century" from 1400, then from 1401; "the 90s" in the two-digit window; "the 2000s" the
      # decade, then the century
      def self.years(node, ctx)
        y = node.short ? two_digit_year(node.year, ctx) : node.year
        b = Calendar.year_start(y) * DAY
        if node.unit == :century
          ctx.note(CENTURY)
          return [Span.new(b, Calendar.year_start(y + 100) * DAY, :century, nil),
                  Span.new(Calendar.year_start(y + 1) * DAY, Calendar.year_start(y + 101) * DAY, :century, nil)]
        end
        decade = Span.new(b, Calendar.year_start(y + 10) * DAY, :decade, nil)
        return [decade] unless y % 100 == 0 && !node.short
        ctx.note(DECADE_CENTURY)
        [decade, Span.new(b, Calendar.year_start(y + 100) * DAY, :century, nil)]
      end

      # D10, D37: the locale's order first (dots are always day first), then the other order when it is also
      # a date. The result is plain dates, month and day in place.
      def self.orders(d, ctx)
        out = []
        [false, true].each { |swap| (x = order(d, ctx, swap)) && !out.include?(x) && out << x }
        ctx.note(ORDER) if out.size > 1
        out
      end

      # The date in the locale's order, or with swap in the other, or nil when that is no date
      def self.order(d, ctx, swap)
        y = d.year && d.short ? two_digit_year(d.year, ctx) : d.year
        m, day = (d.sep == :dot || ctx.locale.day_first) == swap ? [d.month, d.day] : [d.day, d.month]
        return unless m.between?(1, 12) && day.between?(1, y ? Calendar.days_in_month(y, m) : LONGEST[m])
        G::Date.new(y, m, day, nil, false)
      end

      # D23: chronic's window, from 50 years before now to 49 after
      def self.two_digit_year(yy, ctx)
        now = Period.year(ctx.now_local)
        y = now - now % 100 + yy
        if y >= now + 50 then y - 100
        elsif y < now - 50 then y + 100
        else y
        end
      end
    end
  end
end
