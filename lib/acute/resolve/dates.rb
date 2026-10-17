module Acute
  module Resolve
    # Calendar dates: "2026-10-23", "oct 23", "10/23", "23.10.2026", "2015"
    module Dates
      ORDER = Assumption.for(:numeric_date_order)
      LONGEST = [0, 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31].freeze

      def self.spans(d, ctx)
        if d.sep
          out = []
          orders(d, ctx).each { |x| out.concat(spans(x, ctx)) }
          return out
        end
        return Periodic.bare(d, ctx) unless d.year
        y = d.year
        return [] if y < 1 # D18
        if d.day
          return [] unless d.month.between?(1, 12) && d.day.between?(1, Calendar.days_in_month(y, d.month))
          b = Period.civil(y, d.month, d.day)
          [Span.new(b, b + Period::DAY, :day, nil)]
        elsif d.month
          return [] unless d.month.between?(1, 12)
          [Span.new(Period.civil(y, d.month, 1), Period.add(Period.civil(y, d.month, 1), 1, :month), :month, nil)]
        else
          [Span.new(Period.civil(y, 1, 1), Period.civil(y + 1, 1, 1), :year, nil)]
        end
      end

      # D10, D37: the locale's order first (dots are always day first), then the other order when it is also
      # a date. The result is plain dates, month and day in place.
      def self.orders(d, ctx)
        y = d.year && d.short ? two_digit_year(d.year, ctx) : d.year
        first = d.sep == :dot || ctx.locale.day_first ? [d.day, d.month] : [d.month, d.day]
        out = []
        [first, first.reverse].each do |m, day|
          next unless m.between?(1, 12) && day.between?(1, y ? Calendar.days_in_month(y, m) : LONGEST[m])
          x = G::Date.new(y, m, day, nil, false)
          out << x unless out.include?(x)
        end
        ctx.note(ORDER) if out.size > 1
        out
      end

      # D23: chronic's window, from 50 years before now to 49 after
      def self.two_digit_year(yy, ctx)
        now = Period.ymd(ctx.now_local) / 10_000
        y = now - now % 100 + yy
        if y >= now + 50 then y - 100
        elsif y < now - 50 then y + 100
        else y
        end
      end
    end
  end
end
