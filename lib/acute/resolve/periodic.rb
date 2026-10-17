module Acute
  module Resolve
    # Phrases that repeat: "friday" weekly, "the 3rd" monthly, "march 3" and "christmas" yearly, "tonight"
    # daily. Each is found as an occurrence in one cycle (a week, month, year or day), so every rule about
    # which occurrence is meant (D11, D20, D21, D32, D40) is written once, here and in rel.rb.
    module Periodic
      DAY = Period::DAY
      LIMIT = 12 # cycles to search; enough for "feb 29"
      SAME_DAY = Assumption.for(:same_day_or_next)
      SEASON_YEAR = Assumption.for(:season_year)
      SAME_OR_NEXT = [0, DAY].freeze
      SUB_DAY = { G::Clock => true, G::Part => true, G::Range => true }.freeze

      def self.cycle(node)
        case G::KIND[node.class]
        when :weekday, :weekend then :week
        when :date then node.year || node.sep ? nil : node.month ? :year : :month
        when :holiday, :season, :iso_week then :year
        when :part, :clock then :day
        when :nth then G::Unit === node.node && (node.node.unit == :quarter || node.node.unit == :month) ? :year : :month
        when :within then cycle(node.outer)
        when :fuzzy then cycle(node.node)
        end
      end

      # The occurrences in cycle i, the main one first; empty when there is none ("feb 29" in 2027)
      def self.at(node, ctx, i, cyc = cycle(node))
        inside(node, nil, Period.span(cyc, ctx, i), ctx)
      end

      # D11, D23: the current one if it isn't over, else the next; in past context the latest that has begun
      def self.bare(node, ctx, cyc = cycle(node))
        return [] unless cyc
        now = ctx.now_local
        i = Period.index(cyc, ctx, now)
        # The cycles either side of now's are looked at only when an occurrence there can reach into it
        near = contained?(node) ? 0 : 1
        # The weekday or day of the month, under any time or part of day; (today + 4) % 7 is today's weekday
        if cyc == :week || cyc == :month
          day = node
          day = day.outer while G::Within === day && SUB_DAY[day.inner.class]
          today = cyc == :week ? G::Weekday === day && (ctx.today + 4) % 7 == day.wday :
                    G::Date === day && day.day == Calendar.civil_from_days(ctx.today) % 100
          return on_that_day(node, ctx, i, cyc) if today && ctx.past != :back
          # A weekday already gone this week (or, looking back, still to come) can't hold the occurrence
          if near == 0 && !today && G::Weekday === day
            w = i * 7 + ctx.week_start - 4 # the week's first day
            d = w + (day.wday - w - 4) % 7
            i += ctx.past? ? (d > ctx.today ? -1 : 0) : (d < ctx.today ? 1 : 0)
          end
        elsif cyc == :year && near == 0
          # The same for a month already gone this year
          d = node
          d = d.outer while G::Within === d
          if G::Date === d && (m = d.month)
            cur = Period.ymd(now) / 100 % 100
            i += ctx.past? ? (m > cur ? -1 : 0) : (m < cur ? 1 : 0)
          end
        end
        if ctx.past?
          list = last(node, ctx, i + near, cyc) { |s| s.b <= now }
          # D44: in past context, a period under way is the current one, then the one before
          if ctx.past == true && list.size > 0 && list[0].e > now
            b = list[0].b
            list += last(node, ctx, Period.index(cyc, ctx, b) - 1, cyc) { |s| s.b < b }.take(1)
          end
          return list
        end
        list = first(node, ctx, i - near, cyc) { |s| s.e > now }
        # D40, D41: "tonight" said at exactly 00:00 is the rest of the night under way, then the coming one
        if now % DAY == 0 && G::Part === node && node.name == :tonight && list.size > 0 && list[0].b < now
          return [Span.new(now, list[0].e, list[0].grain, nil), *at(node, ctx, i, cyc)]
        end
        list
      end

      # D40, D44: a weekday or a day of the month said on that day, with or without a time: today's, then the
      # next one (in past context the one before); today's comes second once it is over
      def self.on_that_day(node, ctx, i, cyc)
        ctx.note(SAME_DAY)
        cur = at(node, ctx, i, cyc)
        if ctx.past?
          other = last(node, ctx, i - 1, cyc) { true }.take(1)
          cur[0].b <= ctx.now_local ? cur + other : other + cur
        else
          other = first(node, ctx, i + 1, cyc) { true }
          other = other.take(1) if cur.size == 1
          cur[0].e > ctx.now_local ? cur + other : other + cur
        end
      end

      # The first occurrence from cycle i on whose main reading passes the block
      # A while loop: a return from inside a block would unwind through it, which costs more than the search
      def self.first(node, ctx, i, cyc = cycle(node))
        stop = i + LIMIT
        while i < stop
          list = at(node, ctx, i, cyc)
          return list if !list.empty? && yield(list[0])
          return [] if list.empty? && !skips?(node) && !passed_over?(node, ctx, i, cyc) { |s| yield s }
          i += 1
        end
        []
      end

      # Whether every occurrence lies inside its own cycle
      def self.contained?(node)
        case G::KIND[node.class]
        when :weekday, :date, :holiday, :nth then true
        when :clock then node.named != :midnight
        when :within then contained?(node.inner) && contained?(node.outer)
        else false
        end
      end

      # D42: only a date skips the cycles it doesn't exist in ("feb 29", "the 31st"); "5th tuesday in may" is
      # nil, not a later May that has one
      def self.skips?(node) = G::Date === node || G::IsoWeek === node || (G::Within === node && skips?(node.inner))

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
      def self.last(node, ctx, i, cyc = cycle(node))
        stop = i - LIMIT
        while i > stop
          list = at(node, ctx, i, cyc)
          return list if !list.empty? && yield(list[0])
          return [] if list.empty? && !skips?(node) && !passed_over?(node, ctx, i, cyc) { |s| yield s }
          i -= 1
        end
        []
      end

      # The readings of node inside the span s; outer is the node s came from, which a clock needs to see a
      # part of day
      def self.inside(node, outer, s, ctx)
        case G::KIND[node.class]
        when :within
          outers = inside(node.outer, outer, s, ctx)
          return inside(node.inner, node.outer, outers[0], ctx) if outers.size == 1
          outers.flat_map { |o| inside(node.inner, node.outer, o, ctx) }
        when :clock then clock(node, outer, s, ctx)
        when :weekday
          d = s.b / DAY
          d += (node.wday - (d + 4) % 7) % 7 # (d + 4) % 7: d's weekday
          d * DAY < s.e ? [Span.new(d * DAY, d * DAY + DAY, :day, nil)] : []
        when :date then date(node, s, ctx)
        when :part then [Named.part(node.name, Period.day(s.b), ctx)]
        when :weekend
          week = s.grain == :week ? s : Period.span(:week, ctx, Period.index(:week, ctx, s.b))
          Named.weekends(week, ctx)
        when :holiday then (h = Named.holiday(node.name, Period.year(s.b), ctx)) ? within(h, s) : []
        when :season
          y = Period.year(s.b)
          list = within(Named.season(node.name, y, ctx), s)
          return list unless G::Date === outer && s.grain == :year
          # D3: "winter 2026" is the one starting in 2026, then the one ending in it
          before = Named.season(node.name, y - 1, ctx)
          return list unless before.e > s.b
          ctx.note(SEASON_YEAR)
          list << before
        when :nth then nth(node, s, ctx)
        when :iso_week then iso_week(node, Period.year(s.b))
        when :range then Ranges.inside(node, outer, s, ctx)
        when :fuzzy then inside(node.node, outer, s, ctx).flat_map { |x| Fuzzy.apply(node.pos, x, node.node, ctx) }
        else Resolve.spans(node, ctx).select { |x| x.b >= s.b && x.b < s.e }
        end
      end

      # D13: the ISO week of year y, which may start in December before it; week 53 only in a year that has one
      def self.iso_week(node, y)
        d = Calendar.iso_week_one(y) + 7 * (node.week - 1)
        return [] if node.week == 53 && d == Calendar.iso_week_one(y + 1)
        return [Span.new(d * DAY, d * DAY + 7 * DAY, :week, nil)] unless node.day
        d += node.day - 1
        [Span.new(d * DAY, d * DAY + DAY, :day, nil)]
      end

      def self.within(x, s) = x.b >= s.b && x.b < s.e ? [x] : []

      def self.date(node, s, ctx)
        return Dates.orders(node, ctx).flat_map { |d| date(d, s, ctx) } if node.sep
        # A year from January 1st (a cycle, not a fiscal year) needs no civil date
        if s.grain == :year && (y = Calendar.year_if_first(s.b / DAY))
          y = node.year || y
          m = node.month || 1
        else
          p = Period.ymd(s.b)
          y = node.year || p / 10_000
          m = node.month || p / 100 % 100
        end
        if node.day
          return [] unless m >= 1 && m <= 12 && node.day >= 1 && (node.day <= 28 || node.day <= Calendar.days_in_month(y, m))
          b = Calendar.days_from_civil(y, m, node.day) * DAY
          b >= s.b && b < s.e ? [Span.new(b, b + DAY, :day, nil)] : []
        elsif node.month
          return [] unless m >= 1 && m <= 12
          b = Calendar.days_from_civil(y, m, 1) * DAY
          b >= s.b && b < s.e ? [Span.new(b, b + (m == 2 ? Calendar.days_in_month(y, m) : Calendar::MONTH_DAYS[m]) * DAY, :month, nil)] : []
        else
          within(Span.new(Calendar.year_start(y) * DAY, Calendar.year_start(y + 1) * DAY, :year, nil), s)
        end
      end

      # D4, D6 for a clock inside a day; D35, D40 inside a part of the day
      def self.clock(c, outer, s, ctx)
        cands = Clock.candidates(c, ctx, true)
        grain, len = c.seconds ? Clock::SECOND : Clock::MINUTE
        day = s.b - s.b % DAY
        part = part_name(outer)
        # D6: midnight "at the start of" a day is its first moment, "at the end of" its last
        cands = [outer.pos == :start ? 0 : 86_400] if c.named == :midnight && G::Fuzzy === outer && (outer.pos == :start || outer.pos == :end)
        unless part
          return [Span.new(day + cands[0], day + cands[0] + len, grain, nil)] if cands.size == 1
          return cands.map { |secs| Span.new(day + secs, day + secs + len, grain, nil) }
        end
        if c.hour == 12 && !c.meridiem && !c.named # D30, D40: 12 in the morning, 12 at night
          secs = c.min * 60 + c.sec
          cands = [secs + (part == :morning ? 0 : part == :afternoon || part == :lunch ? 43_200 : 86_400)]
        elsif !c.meridiem && part != :night && part != :tonight && part != :lunch
          # D40: the part fixes am or pm, even for a time written with seconds; D35: lunch takes the closer
          pm = part != :morning && part != :early_hours
          cands = [c.hour * 3600 + c.min * 60 + c.sec + (pm ? 43_200 : 0)] if !c.h24 && c.hour >= 1 && c.hour <= 11
          fixed = cands.select { |x| (x >= 43_200) == pm }
          cands = fixed unless fixed.empty?
        end
        best = nil
        best_gap = nil
        cands.each do |secs|
          SAME_OR_NEXT.each do |k| # the next day too, for a part that runs past midnight
            t = day + k + secs
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
