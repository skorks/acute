module Acute
  module Resolve
    # Day words: today, tomorrow, yesterday
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

      def self.whole(d, ctx) = days(d, ctx).map { |day| Span.new(day * 86_400, day * 86_400 + 86_400, :day, nil) }
    end
  end
end
