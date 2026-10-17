module Acute
  module Resolve
    # Times of day: which seconds-of-day a clock can mean, and which day a bare one falls on
    module Clock
      BARE_HOUR = Assumption.for(:bare_hour_window)
      TWELVE = Assumption.for(:twelve_oclock)
      MACHINE = Assumption.for(:machine_time)
      MIDNIGHT_END = Assumption.for(:midnight_end_of_day)
      NEXT = Assumption.for(:next_occurrence)
      PREVIOUS = Assumption.for(:previous_occurrence)
      EQUAL_NOW = Assumption.for(:equal_to_now)

      NOON = [43_200].freeze
      MIDNIGHT = [0].freeze
      # Midnight attached to a day: its end (86400 = the next 00:00) first, then its start
      DAY_MIDNIGHT = [86_400, 0].freeze

      # Seconds of the day, most likely first
      def self.candidates(c, ctx, attached)
        secs = c.min * 60 + c.sec
        if c.named == :noon then NOON
        elsif c.named == :midnight
          return MIDNIGHT unless attached
          ctx.note(MIDNIGHT_END) # D6
          DAY_MIDNIGHT
        elsif c.meridiem
          [((c.hour % 12) + (c.meridiem == :pm ? 12 : 0)) * 3600 + secs]
        elsif c.hour == 0 || c.hour >= 13 || c.h24
          [c.hour * 3600 + secs]
        elsif c.seconds || ctx.machine
          ctx.note(MACHINE) # D29
          [c.hour * 3600 + secs]
        elsif c.hour == 12
          ctx.note(TWELVE) # D30
          [43_200 + secs]
        else
          ctx.note(BARE_HOUR) # D4: 6-11 am, 12 and 1-5 pm, then the other half
          am = c.hour * 3600 + secs
          c.hour >= 6 ? [am, am + 43_200] : [am + 43_200, am]
        end
      end

      def self.grain(c) = c.seconds ? :second : :minute

      def self.length(c) = c.seconds ? 1 : 60

      # D23: the next occurrence of each candidate (the previous one in past context); D36: now counts
      def self.bare(c, ctx)
        cands = candidates(c, ctx, false)
        grain = grain(c)
        len = length(c)
        now_secs = ctx.now_secs
        out = []
        i = 0
        while i < cands.size
          secs = cands[i]
          day = ctx.today
          if secs == now_secs
            ctx.note(EQUAL_NOW) if i == 0
          elsif ctx.past? ? secs > now_secs : secs < now_secs
            day += ctx.past? ? -1 : 1
            ctx.note(ctx.past? ? PREVIOUS : NEXT) if i == 0
          end
          b = day * 86_400 + secs
          out << Span.new(b, b + len, grain, nil)
          i += 1
        end
        out
      end
    end
  end
end
