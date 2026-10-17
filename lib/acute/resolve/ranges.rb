module Acute
  module Resolve
    # Ranges ("monday to friday", "from 3 to 5pm") and open ends ("after friday", "since monday")
    module Ranges
      DAY = Period::DAY
      UNDER_WAY = Assumption.for(:range_under_way)

      def self.spans(node, ctx)
        from = node.from
        to = node.to
        return clocks(meridiem(from, to), to, ctx) if G::Clock === from && G::Clock === to
        return numeric(node, ctx) if G::Date === from && G::Date === to && from.sep && from.sep == to.sep
        f = Resolve.spans(from, ctx)[0]
        return [] unless f
        t = after(to, ctx, f.b)
        list = (x = t && finish(f, t)) ? [x] : []
        under_way(from, to, f, list, ctx) if !ctx.past? && Periodic.cycle(from) == :year
        list
      end

      # D44: a range of dates or months under way ("may to september" in june) is the current one, then the
      # coming one
      def self.under_way(from, to, f, list, ctx)
        now = ctx.now_local
        if f.b > now
          b = Periodic.last(from, ctx, Period.index(:year, ctx, now), :year) { |s| s.b <= now }[0]
          cur = b && (t = after(to, ctx, b.b)) && finish(b, t)
          return unless cur && cur.e > now
          list.unshift(cur)
        else
          # one that starts today is today's alone, as a date said on its day is
          return unless list.size == 1 && list[0].e > now && f.b < ctx.today * DAY
          n = Periodic.first(from, ctx, Period.index(:year, ctx, f.b) + 1, :year) { true }[0]
          coming = n && (t = after(to, ctx, n.b)) && finish(n, t)
          return unless coming
          list << coming
        end
        ctx.note(UNDER_WAY)
      end

      # D10: both ends of "5/1-5/7" are read in the same order, the locale's first
      def self.numeric(node, ctx)
        out = []
        [false, true].each do |swap|
          f = Dates.order(node.from, ctx, swap)
          t = Dates.order(node.to, ctx, swap)
          next unless f && t
          spans(G::Range.new(f, t), ctx).each { |x| out << x unless out.any? { |o| o.b == x.b && o.e == x.e } }
        end
        ctx.note(Dates::ORDER) if out.size > 1
        out
      end

      def self.inside(node, outer, s, ctx)
        from = G::Clock === node.from && G::Clock === node.to ? meridiem(node.from, node.to) : node.from
        f = Periodic.inside(from, outer, s, ctx)[0]
        return [] unless f
        t = G::Clock === node.to ? after(node.to, ctx, f.b) : Periodic.inside(node.to, outer, s, ctx).find { |x| x.b >= f.b }
        (x = t && finish(f, t)) ? [x] : []
      end

      # "2 to 4pm" is 2pm; "11 to 2pm" is 11am
      def self.meridiem(from, to)
        return from if from.meridiem || from.named || !to.meridiem || from.hour > 12
        same = from.hour % 12 < to.hour % 12 || (from.hour % 12 == to.hour % 12 && from.min < to.min)
        G::Clock.new(from.hour, from.min, from.sec, same ? to.meridiem : (to.meridiem == :pm ? :am : :pm), nil,
                     false, from.seconds)
      end

      # D40: a clock range under way is today's, one answer; otherwise the next one (the previous in past
      # context)
      def self.clocks(from, to, ctx)
        now = ctx.now_local
        f = Periodic.inside(from, nil, Period.span(:day, ctx, ctx.today), ctx)[0]
        span = Span.new(f.b, clock_after(to, ctx, f.b), f.grain, nil)
        if ctx.past? ? span.b > now : span.e <= now
          k = ctx.past? ? -DAY : DAY
          span = Span.new(span.b + k, span.e + k, span.grain, nil)
        end
        [span]
      end

      # D9: days and larger include the end; with a clock the end is the stated time
      def self.finish(f, t)
        e = clock?(t) ? t.b : t.e
        e > f.b ? Span.new(f.b, e, f.grain, nil) : nil
      end

      def self.clock?(s) = s.grain == :minute || s.grain == :second

      # The first reading of node from t on
      def self.after(node, ctx, t)
        if G::Clock === node
          grain, len = node.seconds ? Clock::SECOND : Clock::MINUTE
          return Span.new(x = clock_after(node, ctx, t), x + len, grain, nil)
        end
        if (cyc = Periodic.cycle(node))
          return Periodic.first(node, ctx, Period.index(cyc, ctx, t) - 1, cyc) { |s| s.b >= t }[0]
        end
        Resolve.spans(node, ctx)[0]
      end

      # The earliest reading of a clock after t, over every am/pm reading
      def self.clock_after(c, ctx, t)
        d = Period.day(t) * DAY
        best = nil
        Clock.candidates(c, ctx, true).each do |secs|
          [d + secs, d + DAY + secs].each { |x| best = x if x > t && (best.nil? || x < best) }
        end
        best
      end

      # D16, D34: since closes at now and looks back; until opens at now; before ends when X starts; after
      # starts when X ends, or at a clock time itself
      def self.open(node, ctx)
        now = ctx.now_local
        past = ctx.past
        ctx.past = node.dir == :since && :back
        list = Resolve.spans(node.node, ctx)
        ctx.past = past
        list = current(node.node, ctx) || list if node.dir == :after && G::Holiday === node.node
        list.map do |s|
          case node.dir
          when :since then Span.new(s.b, now, s.grain, nil, s.ub, ctx.now)
          when :until then clock?(s) ? Span.new(now, s.b, s.grain, nil, ctx.now, s.ub) : Span.new(now, s.e, s.grain, nil, ctx.now, s.ue)
          when :before then Span.new(nil, s.b, s.grain, nil, nil, s.ub)
          else clock?(s) ? Span.new(s.b, nil, s.grain, nil, s.ub) : Span.new(s.e, nil, s.grain, nil, s.ue)
          end
        end
      end

      # D40: "after christmas" said on Dec 27 is this year's, whose after still holds now. Only holidays: "after
      # january" said in October is next year's (D34)
      def self.current(x, ctx)
        cyc = Periodic.cycle(x)
        list = Periodic.at(x, ctx, Period.index(cyc, ctx, ctx.now_local), cyc)
        list if list.any? && list[0].e <= ctx.now_local
      end
    end
  end
end
