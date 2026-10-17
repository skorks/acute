module Acute
  module Resolve
    # Day words, alone or with a clock
    module Day
      TOMORROW_EARLY = Assumption.for(:tomorrow_after_midnight)
      NIGHT_ENDS = 4 * 3600

      # Day numbers, most likely first
      def self.days(d, ctx)
        today = ctx.today
        # D40: before 04:00 the speaker's "tomorrow" is usually the coming day. Exactly 00:00 is excluded:
        # it is what a Date or a time-less fixture gives as now, which means the day itself (D41)
        if d.offset == 1 && ctx.now_secs > 0 && ctx.now_secs < NIGHT_ENDS
          ctx.note(TOMORROW_EARLY)
          [today, today + 1]
        else
          [today + d.offset]
        end
      end

      def self.whole(d, ctx)
        zone = ctx.zone
        days(d, ctx).map do |day|
          ctx.dst = nil
          b = zone.local_to_utc(day * 86_400, ctx)
          dst = ctx.dst
          Reading.new(b, zone.local_to_utc(day * 86_400 + 86_400, ctx), :day, dst)
        end
      end

      # Day-major: every reading of the first day before any of the next. Readings that land on the same
      # instant ("today at midnight" and "tomorrow" at its start) are kept once.
      def self.moment(m, ctx)
        days = days(m.day, ctx)
        cands = Clock.candidates(m.clock, ctx, true)
        grain = Clock.grain(m.clock)
        len = Clock.length(m.clock)
        zone = ctx.zone
        out = []
        days.each do |day|
          cands.each do |secs|
            ctx.dst = nil
            b = zone.local_to_utc(day * 86_400 + secs, ctx)
            out << Reading.new(b, b + len, grain, ctx.dst) unless out.any? { |r| r.begin == b }
          end
        end
        out
      end
    end
  end
end
