module Acute
  module Resolve
    # "in 3 days", "2 hours ago", "a week from tomorrow", "3 business days after friday"
    module Shift
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
        Resolve.spans(node.anchor, ctx).map do |s|
          Span.new(Period.add(s.b, n, u), Period.add(s.e, n, u), s.grain, s.point && Period.add(s.point, n, u))
        end
      end
    end
  end
end
