module Acute
  module Resolve
    # Ranges ("monday to friday", "from 3 to 5pm") and open ends ("after friday", "since monday")
    module Ranges
      DAY = Period::DAY

      def self.spans(node, ctx)
        from = node.from
        to = node.to
        return clocks(meridiem(from, to), to, ctx) if G::Clock === from && G::Clock === to
        f = Resolve.spans(from, ctx)[0]
        return [] unless f
        t = after(to, ctx, f.b)
        (x = t && finish(f, t)) ? [x] : []
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
        return Span.new(x = clock_after(node, ctx, t), x + Clock.length(node), Clock.grain(node), nil) if G::Clock === node
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
        ctx.past = node.dir == :since
        list = Resolve.spans(node.node, ctx)
        ctx.past = past
        list = current(node.node, ctx) || list if node.dir == :after && G::Holiday === node.node
        list.map do |s|
          case node.dir
          when :since then Span.new(s.b, now, s.grain, nil)
          when :until then Span.new(now, clock?(s) ? s.b : s.e, s.grain, nil)
          when :before then Span.new(nil, s.b, s.grain, nil)
          else Span.new(clock?(s) ? s.b : s.e, nil, s.grain, nil)
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
