module Acute
  module Resolve
    # next / this / last / past, with a unit ("next week", "past 3 days") or a repeating phrase ("next friday")
    module Rel
      DAY = Period::DAY
      NEXT_TWO = Assumption.for(:next_two_readings)
      THIS_PASSED = Assumption.for(:this_passed)
      ROLLING = Assumption.for(:rolling_window)
      CENTURY = Assumption.for(:century_from_00)
      TONIGHT = G::Part.new(:tonight).freeze

      def self.spans(node, ctx)
        x = node.node
        word = node.word
        return periodic(word, x, ctx) unless G::Unit === x || G::Clock === x
        return unit(word, x.unit, ctx) if G::Unit === x && !x.count
        word = :next if word == :coming
        return clock(word, x, ctx) if G::Clock === x
        counted(word, x.count, x.unit, ctx)
      end

      # D20, D21, D32, D40
      def self.periodic(word, x, ctx)
        cyc = Periodic.cycle(x)
        return [] unless cyc
        now = ctx.now_local
        i = Period.index(cyc, ctx, now)
        case word
        when :coming then Periodic.first(x, ctx, i, cyc) { |s| s.b > now } # D40: the first one after now, alone
        when :next
          return Periodic.at(x, ctx, i + 1, cyc) if cyc == :day # D40: "next night" is tomorrow night
          coming = Periodic.first(x, ctx, i, cyc) { |s| s.b > now }
          # D40: said while one is under way, it means the one after, one answer
          return coming if under_way?(x, ctx, i, cyc, now)
          following = Periodic.at(x, ctx, i + 1, cyc)
          out = merge(coming, following)
          ctx.note(NEXT_TWO) if out.size > 1 && following.any? && coming.any? && following[0].b != coming[0].b
          out
        when :this
          cur = Periodic.at(x, ctx, i, cyc)
          return cur if cyc == :day # D1: "this morning" is today's, even once it has passed
          prev = Periodic.at(x, ctx, i - 1, cyc)
          return prev if prev.any? && prev[0].b <= now && prev[0].e > now # D8: the weekend under way
          return cur if cur.empty? || cur[0].e > now
          ctx.note(THIS_PASSED)
          merge(Periodic.first(x, ctx, i + 1, cyc) { |s| s.e > now }, cur)
        else
          x = TONIGHT if G::Part === x && x.name == :night # D1: last night starts at 17:00
          Periodic.last(x, ctx, i, cyc) { |s| s.e <= now }
        end
      end

      def self.under_way?(x, ctx, i, cyc, now)
        [i - 1, i].any? do |j|
          s = Periodic.at(x, ctx, j, cyc)[0]
          s && s.b <= now && s.e > now
        end
      end

      # The main readings first, then the alternatives of each
      def self.merge(a, b)
        out = []
        [a.first(1), b.first(1), a.drop(1), b.drop(1)].each do |list|
          list.each { |s| out << s unless out.any? { |o| o.b == s.b && o.e == s.e } }
        end
        out
      end

      # "next week", "this month", "last year"; D38 for hours and minutes; D31 for "past week"
      def self.unit(word, u, ctx)
        now = ctx.now_local
        return counted(word == :this || word == :coming ? :next : word, 2, :week, ctx) if u == :fortnight # D40
        return counted(:past, 1, u, ctx) if word == :past
        k = word == :next || word == :coming ? 1 : word == :this ? 0 : -1
        if u == :business_day
          b = Period.business(Period.day(now) * DAY, k)
          return [Span.new(b, b + DAY, :day, nil)]
        end
        cur = Period.unit(u, ctx, now)
        b = Period.add(cur.b, k, u)
        calendar = Span.new(b, Period.add(b, 1, u), cur.grain, nil)
        if u == :century # D12, D44
          ctx.note(CENTURY)
          return [calendar, Span.new(Period.add(b, 1, :year), Period.add(calendar.e, 1, :year), cur.grain, nil)]
        end
        if u == :decade && k != 0 && word != :coming # D40: the ten years from now first; "this coming" is the next to start
          rolling = k > 0 ? Span.new(now, Period.add(now, 1, u), u, nil) : Span.new(Period.add(now, -1, u), now, u, nil)
          return [calendar] if rolling.b == calendar.b
          ctx.note(ROLLING)
          return [rolling, calendar]
        end
        # D42: not "next second", whose rolling reading would be this second
        return [calendar] unless (u == :hour || u == :minute) && k != 0
        ctx.note(ROLLING)
        [k > 0 ? window(ctx, Period::SECONDS[u], u) : window(ctx, -Period::SECONDS[u], u), calendar]
      end

      # D7, D31: rolling from now first, then whole units: the next N, or the N ending with this one and the N
      # before it
      def self.counted(word, n, u, ctx)
        n, u = Period.whole(n, u)
        if u == :fortnight
          n *= 2
          u = :week
        end
        now = ctx.now_local
        ctx.note(ROLLING)
        if word == :next || word == :this
          return [window(ctx, n * Period::SECONDS[u], u)] if Period::SECONDS[u]
          out = [Span.new(now, Period.add(now, n, u), u, nil)]
          b = Period.add(Period.unit(u, ctx, now).b, 1, u)
          out << Span.new(b, Period.add(b, n, u), u, nil)
        else
          return [window(ctx, -n * Period::SECONDS[u], u)] if Period::SECONDS[u]
          out = [Span.new(Period.add(now, -n, u), now, u, nil)]
          cur = Period.unit(u, ctx, now).b
          e = Period.add(cur, 1, u)
          out << Span.new(Period.add(e, -n, u), e, u, nil) << Span.new(Period.add(cur, -n, u), cur, u, nil)
        end
      end

      # From now to secs away, either way. D23: hours and smaller are absolute time, so "the last 48 hours" across
      # a DST change is still 48 hours
      def self.window(ctx, secs, unit)
        utc = ctx.now + secs
        t = ctx.local(utc)
        secs > 0 ? Span.new(ctx.now_local, t, unit, nil, ctx.now, utc) : Span.new(t, ctx.now_local, unit, nil, utc, ctx.now)
      end

      # D18: "next 3pm" is the nearest one after now, "last 3pm" the nearest before
      def self.clock(word, c, ctx)
        return Clock.bare(c, ctx) if word == :next || word == :this
        past = ctx.past
        ctx.past = :back
        out = Clock.bare(c, ctx)
        ctx.past = past
        out
      end
    end
  end
end
