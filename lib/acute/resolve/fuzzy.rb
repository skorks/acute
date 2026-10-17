module Acute
  module Resolve
    # early / mid / late / start / end of a period (D2, D35)
    module Fuzzy
      DAY = Period::DAY
      HOUR = 3600

      # D42: a repeating one is picked by the fuzzy part, so "early morning" said at 10:30 is tomorrow's
      def self.spans(node, ctx)
        return Periodic.bare(node, ctx) if Periodic.cycle(node.node)
        Resolve.spans(node.node, ctx).flat_map { |s| apply(node.pos, s, node.node, ctx) }
      end

      def self.apply(pos, s, x, ctx)
        part = Periodic.part_name(x)
        return [part(pos, s, part)] if part
        case s.grain
        when :month then [days(pos, s, 10)]
        when :year, :quarter, :season then [months(pos, s, ctx)]
        when :week then [week(pos, s, ctx)]
        when :day then [day(pos, s)]
        when :decade
          y = Period.year(s.b)
          from, to = { early: [0, 4], mid: [4, 7], late: [7, 10], start: [0, 1], end: [9, 10] }.fetch(pos)
          [Span.new(Period.civil(y + from, 1, 1), Period.civil(y + to, 1, 1), :year, nil)]
        else [s]
        end
      end

      # D2: thirds of a month (1-10, 11-20, 21-end); start and end are the first and last day
      def self.days(pos, s, third)
        case pos
        when :start then Span.new(s.b, s.b + DAY, :day, nil)
        when :end then Span.new(s.e - DAY, s.e, :day, nil)
        when :early then Span.new(s.b, s.b + third * DAY, :day, nil)
        when :mid then Span.new(s.b + third * DAY, s.b + 2 * third * DAY, :day, s.b + 14 * DAY)
        else Span.new(s.b + 2 * third * DAY, s.e, :day, nil)
        end
      end

      # D2: a year in thirds of four months; a quarter or season in months
      def self.months(pos, s, ctx)
        return days(pos, s, 0) if pos == :start || pos == :end
        n = s.grain == :year ? 4 : 1
        k = { early: 0, mid: 1, late: 2 }.fetch(pos)
        b = Period.add(s.b, k * n, :month)
        Span.new(b, k == 2 ? s.e : Period.add(b, n, :month), :month, nil)
      end

      # D2: early Mon-Tue, mid Wed-Thu, late Fri-Sat; end of week is Friday; D38: start is the locale's
      # first day
      def self.week(pos, s, ctx)
        mon = s.b + ((1 - ctx.week_start) % 7) * DAY
        case pos
        when :start then Span.new(s.b, s.b + DAY, :day, nil)
        when :end then Span.new(mon + 4 * DAY, mon + 5 * DAY, :day, nil)
        else
          b = mon + { early: 0, mid: 2, late: 4 }.fetch(pos) * DAY
          Span.new(b, b + 2 * DAY, :day, nil)
        end
      end

      # D2: end of day is 23:59:59
      def self.day(pos, s)
        case pos
        when :start then Span.new(s.b, s.b + 1, :second, nil)
        when :end then Span.new(s.e - 1, s.e, :second, nil)
        else
          b = s.b + { early: 0, mid: 8, late: 16 }.fetch(pos) * HOUR
          Span.new(b, b + 8 * HOUR, :hour, nil)
        end
      end

      # D1: early morning 04-08 and late night 22-04; D35: otherwise halves; D40: mid is the middle third
      def self.part(pos, s, name)
        day = Period.day(s.b) * DAY
        if pos == :early && name == :morning then Span.new(day + 4 * HOUR, day + 8 * HOUR, :hour, day + 6 * HOUR)
        elsif pos == :late && (name == :night || name == :tonight)
          Span.new(day + 22 * HOUR, day + 28 * HOUR, :hour, day + 23 * HOUR)
        else
          len = s.e - s.b
          case pos
          when :early, :start then Span.new(s.b, s.b + len / 2, :hour, nil)
          when :mid then Span.new(s.b + len / 3, s.b + 2 * len / 3, :hour, nil)
          else Span.new(s.b + len / 2, s.e, :hour, nil)
          end
        end
      end
    end
  end
end
