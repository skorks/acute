module Acute
  module Resolve
    # "in 3 days", "2 hours ago", "a week from tomorrow", "3 business days after friday"
    module Shift
      FINE = { second: 0, minute: 1, hour: 2 }.freeze

      # D23: hours and smaller are absolute time; days and larger are wall-clock arithmetic that keeps the
      # time of day. With no anchor the result is an instant.
      def self.spans(node, ctx)
        n, u = Period.whole(node.count, node.unit)
        unless node.anchor
          if (len = Period::SECONDS[u])
            utc = ctx.now + n * len
            t = ctx.local(utc)
            return [Span.new(t, t + 1, :second, nil, utc, utc + 1)]
          end
          t = Period.add(ctx.now_local, n, u, ctx)
          return [Span.new(t, t + 1, :second, nil)]
        end
        len = Period::SECONDS[u]
        Resolve.spans(node.anchor, ctx).map do |s|
          next calendar(s, n, u, ctx) unless len
          # D44: from the anchor's instant, at a grain no coarser than the unit
          ub = (s.ub || ctx.zone.local_to_utc(s.b, ctx, ctx.dst_policy)) + n * len
          grain = s.grain
          size = s.ue ? s.ue - s.ub : s.e - s.b
          if !(r = FINE[grain]) || r > FINE[u]
            grain = u
            size = len
          end
          Span.new(ctx.local(ub), ctx.local(ub + size), grain, nil, ub, ub + size)
        end
      end

      RANK = { second: 0, minute: 1, hour: 2, day: 3, business_day: 3, weekend: 4, week: 4, fortnight: 4, month: 5,
               quarter: 6, season: 6, year: 7, decade: 8, century: 9 }.freeze
      GRAIN = { business_day: :day, fortnight: :week }.freeze

      # D44: a shift in days or longer from a longer anchor counts from its start at the unit's grain ("1 day
      # before next month"); a day or less keeps its length ("a month from today" on 28 February is 28 March)
      def self.calendar(s, n, u, ctx)
        b = Period.add(s.b, n, u, ctx)
        rank = RANK.fetch(s.grain)
        return Span.new(b, Period.add(b, 1, u, ctx), GRAIN[u] || u, nil) if rank > RANK.fetch(u)
        return Span.new(b, b + s.e - s.b, s.grain, s.point && s.point - s.b + b) if rank <= 3
        Span.new(b, Period.add(s.e, n, u, ctx), s.grain, s.point && Period.add(s.point, n, u, ctx))
      end

      # D44: "3 fridays from now" is the third Friday after now, not counting today's; "2 weekends ago" the
      # second whose end has passed. One a cycle, so the nth is n - 1 cycles on from the first. From an anchor
      # with alternatives, each gives one ("friday after next").
      def self.counted(node, ctx)
        n = node.n
        return nth_from(node.node, n, ctx.now_local + (n > 0 ? 1 : 0), ctx) unless node.anchor
        a = Resolve.spans(node.anchor, ctx)
        return nth_from(node.node, n, n > 0 ? a[0].e : a[0].b, ctx) if a.size <= 1 && !a.empty?
        a.flat_map { |s| nth_from(node.node, n, n > 0 ? s.e : s.b, ctx).first(1) }.uniq
      end

      # D48: one a cycle, so the n nearest lie within n cycles of the anchor's; nearest by start, the earlier
      # on a tie
      def self.closest(node, ctx)
        cyc = Periodic.cycle(node.node)
        a = Resolve.spans(node.anchor, ctx)
        return [] if !cyc || a.empty?
        t = a[0].b
        i = Period.index(cyc, ctx, t)
        all = ((i - node.n)..(i + node.n)).flat_map { |j| Periodic.at(node.node, ctx, j, cyc) }
        all.sort_by { |s| [(s.b - t).abs, s.b] }[node.n - 1, 1] || []
      end

      def self.nth_from(x, n, t, ctx)
        cyc = Periodic.cycle(x)
        i = Period.index(cyc, ctx, t)
        first = n > 0 ? Periodic.first(x, ctx, i, cyc) { |s| s.b >= t } : Periodic.last(x, ctx, i, cyc) { |s| s.e <= t }
        return first if first.empty? || n.abs == 1
        Periodic.at(x, ctx, Period.index(cyc, ctx, first[0].b) + n - (n <=> 0), cyc)
      end
    end
  end
end
