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
          t = Period.add(ctx.now_local, n, u)
          return [Span.new(t, t + 1, :second, nil)]
        end
        len = Period::SECONDS[u]
        Resolve.spans(node.anchor, ctx).map do |s|
          next Span.new(Period.add(s.b, n, u), Period.add(s.e, n, u), s.grain, s.point && Period.add(s.point, n, u)) unless len
          # D44: from the anchor's instant, at a grain no coarser than the unit
          ub = (s.ub || ctx.zone.local_to_utc(s.b, ctx)) + n * len
          grain = s.grain
          size = s.ue ? s.ue - s.ub : s.e - s.b
          if !(r = FINE[grain]) || r > FINE[u]
            grain = u
            size = len
          end
          Span.new(ctx.local(ub), ctx.local(ub + size), grain, nil, ub, ub + size)
        end
      end
    end
  end
end
