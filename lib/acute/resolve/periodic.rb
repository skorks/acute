module Acute
  module Resolve
    # Phrases that repeat: "friday" weekly, "the 3rd" monthly, "march 3" and "christmas" yearly, "tonight"
    # daily. Each is found as an occurrence in one cycle (a week, month, year or day), so every rule about
    # which occurrence is meant (D11, D20, D21, D32, D40) is written once, here and in rel.rb.
    module Periodic
      DAY = Period::DAY
      LIMIT = 12 # cycles to search; enough for "feb 29"
      SAME_DAY = Assumption.for(:same_day_or_next)

      def self.cycle(node)
        case node
        when G::Weekday, G::Weekend then :week
        when G::Date then node.year || node.sep ? nil : node.month ? :year : :month
        when G::Holiday, G::Season then :year
        when G::Part, G::Clock then :day
        when G::Nth then G::Unit === node.node && (node.node.unit == :quarter || node.node.unit == :month) ? :year : :month
        when G::Within then cycle(node.outer)
        when G::Fuzzy then cycle(node.node)
        end
      end

      # The occurrences in cycle i, the main one first; empty when there is none ("feb 29" in 2027)
      def self.at(node, ctx, i, cyc = cycle(node))
        memo = ctx.occurrences(node)
        memo[i] ||= inside(node, nil, Period.span(cyc, ctx, i), ctx)
      end

      # D11, D23: the current one if it isn't over, else the next; in past context the latest that has begun
      def self.bare(node, ctx)
        cyc = cycle(node)
        return [] unless cyc
        now = ctx.now_local
        i = Period.index(cyc, ctx, now)
        if ctx.past?
          i += 1
          LIMIT.times do
            list = at(node, ctx, i, cyc)
            return list if !list.empty? && list[0].b <= now
            return [] if list.empty? && !skips?(node) && !passed_over?(node, ctx, i, cyc) { |s| s.b <= now }
            i -= 1
          end
          return []
        end
        list = first(node, ctx, i - 1, cyc) { |s| s.e > now }
        # D40, D41: "tonight" said at exactly 00:00 is the rest of the night under way, then the coming one
        if now % DAY == 0 && G::Part === node && node.name == :tonight && list.size > 0 && list[0].b < now
          return [Span.new(now, list[0].e, list[0].grain, nil), *at(node, ctx, i, cyc)]
        end
        # D40: a day said on that day is today, then the next one
        if list.size > 0 && list[0].grain == :day && list[0].b <= now
          ctx.note(SAME_DAY)
          after = first(node, ctx, i, cyc) { |s| s.b > now }
          list += after.take(1)
        end
        list
      end

      # The first occurrence from cycle i on whose main reading passes the block
      def self.first(node, ctx, i, cyc = cycle(node), &pass)
        LIMIT.times do
          list = at(node, ctx, i, cyc)
          return list if !list.empty? && pass.(list[0])
          return [] if list.empty? && !skips?(node) && !passed_over?(node, ctx, i, cyc, &pass)
          i += 1
        end
        []
      end

      # D42: only a date skips the cycles it doesn't exist in ("feb 29", "the 31st"); "5th tuesday in may" is
      # nil, not a later May that has one
      def self.skips?(node) = G::Date === node || (G::Within === node && skips?(node.inner))

      # D37: a weekday with a date filters the date's own occurrence, so a cycle whose date falls on another
      # weekday is passed over only when the date's occurrence there would be
      def self.passed_over?(node, ctx, i, cyc)
        date = unfiltered(node)
        return false if date.equal?(node)
        list = inside(date, nil, Period.span(cyc, ctx, i), ctx)
        !list.empty? && !yield(list[0])
      end

      def self.unfiltered(node)
        return node unless G::Within === node
        return node.outer if G::Weekday === node.inner && G::Date === node.outer
        outer = unfiltered(node.outer)
        outer.equal?(node.outer) ? node : G::Within.new(node.inner, outer)
      end

      # The latest occurrence at or before cycle i whose main reading passes the block
      def self.last(node, ctx, i, cyc = cycle(node), &pass)
        LIMIT.times do
          list = at(node, ctx, i, cyc)
          return list if !list.empty? && pass.(list[0])
          return [] if list.empty? && !skips?(node) && !passed_over?(node, ctx, i, cyc, &pass)
          i -= 1
        end
        []
      end

      # The readings of node inside the span s; outer is the node s came from, which a clock needs to see a
      # part of day
      def self.inside(node, outer, s, ctx)
        case node
        when G::Clock then clock(node, outer, s, ctx)
        when G::Weekday
          d = Period.day(s.b)
          d += (node.wday - Calendar.weekday(d)) % 7
          d * DAY < s.e ? [Span.new(d * DAY, d * DAY + DAY, :day, nil)] : []
        when G::Date then date(node, s, ctx)
        when G::Part then [Named.part(node.name, Period.day(s.b), ctx)]
        when G::Weekend
          week = s.grain == :week ? s : Period.span(:week, ctx, Period.index(:week, ctx, s.b))
          Named.weekends(week, ctx)
        when G::Holiday then within(Named.holiday(node.name, Period.ymd(s.b) / 10_000, ctx), s)
        when G::Season then within(Named.season(node.name, Period.ymd(s.b) / 10_000, ctx), s)
        when G::Nth then nth(node, s, ctx)
        when G::Within
          inside(node.outer, outer, s, ctx).flat_map { |o| inside(node.inner, node.outer, o, ctx) }
        when G::Range then Ranges.inside(node, outer, s, ctx)
        when G::Fuzzy then inside(node.node, outer, s, ctx).flat_map { |x| Fuzzy.apply(node.pos, x, node.node, ctx) }
        else Resolve.spans(node, ctx).select { |x| x.b >= s.b && x.b < s.e }
        end
      end

      def self.within(x, s) = x.b >= s.b && x.b < s.e ? [x] : []

      def self.date(node, s, ctx)
        return Dates.orders(node, ctx).flat_map { |d| date(d, s, ctx) } if node.sep
        p = Period.ymd(s.b)
        y = node.year || p / 10_000
        m = node.month || p / 100 % 100
        if node.day
          return [] unless m.between?(1, 12) && node.day.between?(1, Calendar.days_in_month(y, m))
          b = Period.civil(y, m, node.day)
          within(Span.new(b, b + DAY, :day, nil), s)
        elsif node.month
          return [] unless m.between?(1, 12)
          b = Period.civil(y, m, 1)
          within(Span.new(b, Period.add(b, 1, :month), :month, nil), s)
        else
          within(Span.new(Period.civil(y, 1, 1), Period.civil(y + 1, 1, 1), :year, nil), s)
        end
      end

      # "second tuesday of march", "last friday of the month", "Q3", "first day of next month"
      def self.nth(node, s, ctx)
        n = node.n
        x = node.node
        out = case x
              when G::Weekday
                first = Period.day(s.b)
                last = Period.day(s.e) - 1
                d = n > 0 ? Named.nth_weekday(first, x.wday, n) : last - (Calendar.weekday(last) - x.wday) % 7
                [Span.new(d * DAY, d * DAY + DAY, :day, nil)]
              when G::Weekend
                sat = Named.nth_weekday(Period.day(s.b), 6, n > 0 ? n : 1)
                Named.weekends(Period.span(:week, ctx, Period.index(:week, ctx, sat * DAY)), ctx)
              else
                unit = x.unit
                unit = :day if unit == :business_day
                if Period::DAYS[unit]
                  b = n > 0 ? s.b + (n - 1) * Period::DAYS[unit] * DAY : s.e - Period::DAYS[unit] * DAY
                  [Span.new(b, b + Period::DAYS[unit] * DAY, unit, nil)]
                else
                  b = n > 0 ? Period.add(s.b, n - 1, unit) : Period.add(s.e, -1, unit)
                  [Span.new(b, Period.add(b, 1, unit), unit, nil)]
                end
              end
        out.select { |o| o.b >= s.b && o.e <= s.e }
      end

      # D4, D6 for a clock inside a day; D35, D40 inside a part of the day
      def self.clock(c, outer, s, ctx)
        cands = Clock.candidates(c, ctx, true)
        len = Clock.length(c)
        grain = Clock.grain(c)
        day = Period.day(s.b) * DAY
        part = part_name(outer)
        return cands.map { |secs| Span.new(day + secs, day + secs + len, grain, nil) } unless part
        if c.hour == 12 && !c.meridiem && !c.named # D30, D40: 12 in the morning, 12 at night
          cands = part == :morning ? [0] : part == :afternoon || part == :lunch ? [43_200] : [86_400]
        elsif !c.meridiem && part != :night && part != :tonight
          pm = part != :morning && part != :early_hours
          fixed = cands.select { |x| (x >= 43_200) == pm }
          cands = fixed unless fixed.empty?
        end
        best = nil
        best_gap = nil
        cands.each do |secs|
          [day + secs, day + DAY + secs].each do |t|
            gap = t < s.b ? s.b - t : t >= s.e ? t - s.e : -1
            next if best_gap && gap >= best_gap
            best = t
            best_gap = gap
          end
        end
        [Span.new(best, best + len, grain, nil)]
      end

      def self.part_name(node)
        case node
        when G::Part then node.name
        when G::Rel, G::Fuzzy then part_name(node.node)
        when G::Within then part_name(node.inner)
        end
      end
    end
  end
end
