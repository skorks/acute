require "date"

module Acute
  class Rule
    # @api private
    MAX_OCCURRENCES = 1_000 # R19
    STEPS = 100_000 # R19

    # R16: the next occurrence after `after` (by default the now the rule was read at), or with n the next n as an
    # Array: Times in the rule's zone, or Dates for a rule of whole days. nil or fewer when the rule ends; nil past a
    # limit (R19), which next! explains.
    def next(n = nil, after: now)
      out = listing(n || 1, after)
      return if Failure === out
      n ? out : out[0]
    end

    def next!(n = nil, after: now)
      out = raising(listing(n || 1, after))
      n ? out : out[0]
    end

    # R16: the occurrences from `from` up to `to`, `to` left out. A Date stands for its whole day.
    def between(from, to)
      out = window(from, to)
      out unless Failure === out
    end

    def between!(from, to) = raising(window(from, to))

    # R16: every occurrence in order, lazily, from DTSTART or after `after`. It ends with the rule, or when R19's
    # steps pass without one.
    def each(after: nil)
      return enum_for(:each, after: after) unless block_given?
      x = expander
      x.walk(after.nil? ? x.first : x.after(after)) do |o|
        yield x.out(o)
        x.refill
      end
      self
    rescue Expand::Exhausted
      self
    end

    private

    def expander = Expand.new(@parts, @zone, @start, @timed, @count, @until, @exdates, @dst)

    def raising(out)
      raise Explain.error(out, "") if Failure === out
      out
    end

    def listing(n, after)
      raise ArgumentError, "n must be an Integer of 0 or more, got #{n.inspect}" unless Integer === n && n >= 0
      return Failure.new(:occurrence_limit, 0, 0) if n > MAX_OCCURRENCES
      out = []
      return out if n == 0
      x = expander
      x.walk(x.after(after)) do |o|
        out << x.out(o)
        break if out.size == n
      end
      out
    rescue Expand::Exhausted
      Failure.new(:step_limit, 0, 0)
    end

    def window(from, to)
      x = expander
      lo, hi = x.span(from, to)
      out = []
      x.walk(lo) do |o|
        break unless x.before?(o, hi)
        return Failure.new(:occurrence_limit, 0, 0) if out.size == MAX_OCCURRENCES
        out << x.out(o)
      end
      out
    rescue Expand::Exhausted
      Failure.new(:step_limit, 0, 0)
    end

    # R17: RFC 5545 expansion of a Rule, one call's worth. An occurrence is [utc, wall] when the rule is timed, else
    # a day number; walk yields them in order.
    class Expand
      DAY = 86_400
      SUB = { hourly: 3600, minutely: 60, secondly: 1 }.freeze
      MARGIN = 2 * 3600 # more than any clock change, so a period starting the local day before is looked at
      EPOCH_JD = 2_440_588
      NONE = [].freeze
      Notes = Struct.new(:dst)
      class Exhausted < StandardError; end

      def initialize(parts, zone, start, timed, count, until_, exdates, dst)
        @zone = Zone.for(zone)
        @freq = parts.freq
        @interval = parts.interval
        @start = start
        @timed = timed
        @count = count
        @until = until_
        @exdates = exdates
        @dst = dst
        @policy = dst == :reject ? nil : dst
        @notes = Notes.new
        @steps = STEPS
        @d0 = timed ? start.div(DAY) : start
        @month = parts.month
        @monthdays = parts.monthdays
        @days = parts.days
        @nths = parts.nths
        @setpos = parts.setpos
        @secs = parts.secs.empty? && timed && !SUB[@freq] ? [start % DAY] : parts.secs.sort
        derive
        @anchor = @zone.local_to_utc(start, @notes, @policy) if timed
      end

      def first = @timed ? @anchor : @d0

      def refill = @steps = STEPS

      # The lowest occurrence after x: an instant after it, or a day still under way at it (R2); a Date is its
      # whole day
      def after(x)
        if plain_date?(x)
          day = x.jd - EPOCH_JD + 1
          return @timed ? day_start(day) : day
        end
        t = epoch(x).floor
        @timed ? t + 1 : local_day(t)
      end

      # [lowest, past the highest] of the occurrences from `from` up to `to`; a day counts when any of it is
      def span(from, to)
        lo = if plain_date?(from)
               day = from.jd - EPOCH_JD
               @timed ? day_start(day) : day
             else
               t = epoch(from).ceil
               @timed ? t : local_day(t)
             end
        hi = if plain_date?(to)
               day = to.jd - EPOCH_JD + 1
               @timed ? day_start(day) : day
             else
               t = epoch(to).ceil
               @timed ? t : local_day(t - 1) + 1
             end
        [lo, hi]
      end

      def before?(o, hi) = @timed ? o[0] < hi : o < hi

      def out(o) = @timed ? Time.at(o[0], in: @zone.offset_at(o[0])) : ::Date.jd(o + EPOCH_JD)

      def walk(lo, &) = SUB[@freq] ? sub_walk(lo, &) : day_walk(lo, &)

      private

      # R17: a part the rule doesn't name comes from DTSTART, as RFC 5545 says
      def derive
        ymd = Calendar.civil_from_days(@d0)
        bare = @monthdays.empty? && @days.empty? && @nths.empty?
        case @freq
        when :weekly
          @days = [Calendar.weekday(@d0)] if @days.empty?
        when :monthly
          @monthdays = [ymd % 100] if bare
        when :yearly
          if bare
            @month ||= ymd / 100 % 100
            @monthdays = [ymd % 100]
          end
        end
      end

      def plain_date?(x) = Date === x && !(DateTime === x)

      def epoch(x)
        return x.to_r if Time === x
        return x.to_time.to_r if x.respond_to?(:to_time)
        raise ArgumentError, "expected a Time or a Date, got #{x.class}"
      end

      def local_day(t) = (t + @zone.offset_at(t)).div(DAY)

      def day_start(day) = @zone.local_to_utc(day * DAY, @notes)

      def spend(n)
        raise Exhausted if (@steps -= n) < 0
      end

      # Daily to yearly: period k is the interval's k-th day, week (from Monday), month or year after DTSTART's
      def day_walk(lo)
        k = @count ? 0 : first_period(lo)
        n = 0
        loop do
          list = period(k)
          spend(list.size + 1)
          if @timed
            return if @until && (@first - 1) * DAY > @until
            zoned(list).each do |utc, wall|
              next if wall < @start
              return nil if @until && utc > @until
              return nil if @count && (n += 1) > @count
              yield [utc, wall] unless utc < lo || @exdates.include?(wall)
            end
          else
            return if @until && @first > @until
            list.each do |day|
              next if day < @start
              return nil if @until && day > @until
              return nil if @count && (n += 1) > @count
              yield day unless day < lo || @exdates.include?(day)
            end
          end
          k += 1
        end
      end

      # The period holding lo's day, or the last one before it, so a jump skips what comes before lo
      def first_period(lo)
        day = @timed ? local_day(lo - MARGIN) : lo
        i = case @freq
            when :daily then day - @d0
            when :weekly then (monday(day) - monday(@d0)) / 7
            when :monthly then month_index(day) - month_index(@d0)
            else year(day) - year(@d0)
            end
        k = i.div(@interval)
        k < 0 ? 0 : k
      end

      # Period k's candidates in order, after BYSETPOS: wall seconds when timed, else days
      def period(k)
        step = k * @interval
        days = case @freq
               when :daily
                 @first = @d0 + step
                 day_ok?(@first) ? [@first] : NONE
               when :weekly
                 @first = monday(@d0) + 7 * step
                 list = @days.map { @first + (_1 + 6) % 7 }.sort
                 @month ? list.select { month_of(_1) == @month } : list
               when :monthly
                 y, m = (month_index(@d0) + step).divmod(12)
                 @first = Calendar.days_from_civil(y, m + 1, 1)
                 @month && @month != m + 1 ? NONE : in_month(@first, Calendar.days_in_month(y, m + 1))
               else
                 y = year(@d0) + step
                 @first = Calendar.year_start(y)
                 if @month
                   in_month(Calendar.days_from_civil(y, @month, 1), Calendar.days_in_month(y, @month))
                 elsif @monthdays.empty?
                   by_weekday(@first, Calendar.year_start(y + 1)).sort.uniq # RFC 5545: an ordinal counts in the year
                 else
                   (1..12).flat_map { in_month(Calendar.days_from_civil(y, _1, 1), Calendar.days_in_month(y, _1)) }
                 end
               end
        list = @timed ? days.flat_map { |d| @secs.map { d * DAY + _1 } } : days
        @setpos ? @setpos.filter_map { list[_1 > 0 ? _1 - 1 : _1] }.uniq.sort : list
      end

      # R18: wall times to [utc, wall] by the dst: policy; :reject leaves out a skipped or repeated time
      def zoned(walls)
        shifted = false
        out = []
        walls.each do |w|
          @notes.dst = nil
          utc = @zone.local_to_utc(w, @notes, @policy)
          if @notes.dst
            next if @dst == :reject
            shifted = true
          end
          out << [utc, w]
        end
        return out unless shifted && out.size > 1
        # A skipped time moved forward can land on a later one, which it then is
        out.sort_by!(&:first)
        out.uniq!(&:first)
        out
      end

      # R18: hourly and finer step in elapsed time from DTSTART (D23)
      def sub_walk(lo)
        unit = SUB[@freq]
        step = unit * @interval
        a = @anchor
        if @secs.empty? && every_day?
          k = lo <= a ? 0 : (lo - a + step - 1).div(step) # each step is one occurrence, so k is also the count
          loop do
            spend(1)
            t = a + k * step
            return if @count && k >= @count
            return if @until && t > @until
            wall = t + @zone.offset_at(t)
            yield [t, wall] unless @exdates.include?(wall)
            k += 1
          end
        end
        p0 = a - @start % unit # the start of DTSTART's hour, minute or second
        n = 0
        day = (@count ? @d0 : [local_day(lo - MARGIN), @d0].max) - 1
        loop do
          day += 1
          spend(1)
          s0 = day_start(day)
          return if @until && s0 > @until
          next unless day_ok?(day)
          if @secs.empty?
            s1 = day_start(day + 1)
            t = s0 <= a ? a : a + (s0 - a + step - 1).div(step) * step
            while t < s1
              spend(1)
              return if @until && t > @until
              return if @count && (n += 1) > @count
              wall = t + @zone.offset_at(t)
              yield [t, wall] unless t < lo || @exdates.include?(wall)
              t += step
            end
          else
            zoned(@secs.map { day * DAY + _1 }).each do |t, wall|
              spend(1)
              next if t < a || !((t - p0).div(unit) % @interval).zero?
              return nil if @until && t > @until
              return nil if @count && (n += 1) > @count
              yield [t, wall] unless t < lo || @exdates.include?(wall)
            end
          end
        end
      end

      def every_day? = @month.nil? && @monthdays.empty? && @days.empty? && @nths.empty?

      # BYMONTH, BYMONTHDAY and BYDAY as limits on one day
      def day_ok?(d)
        return true if every_day?
        ymd = Calendar.civil_from_days(d)
        m = ymd / 100 % 100
        return false if @month && @month != m
        dim = Calendar.days_in_month(ymd / 10_000, m)
        unless @monthdays.empty?
          md = ymd % 100
          return false unless @monthdays.any? { (_1 > 0 ? _1 : dim + _1 + 1) == md }
        end
        first = d - ymd % 100 + 1
        (@days.empty? && @nths.empty?) || weekday_ok?(d, first, first + dim)
      end

      # A month's days: BYMONTHDAY, limited by BYDAY, or BYDAY alone
      def in_month(first, dim)
        z = first + dim
        list = if @monthdays.empty?
                 by_weekday(first, z)
               else
                 days = @monthdays.filter_map do |md|
                   x = md > 0 ? md : dim + md + 1
                   first + x - 1 if x >= 1 && x <= dim
                 end
                 @days.empty? && @nths.empty? ? days : days.select { weekday_ok?(_1, first, z) }
               end
        list.size > 1 ? list.sort.uniq : list
      end

      # The days from a up to z on a BYDAY weekday, an ordinal one counted within them
      def by_weekday(a, z)
        out = []
        @days.each do |w|
          d = a + (w - Calendar.weekday(a)) % 7
          while d < z
            out << d
            d += 7
          end
        end
        @nths.each do |n, w|
          d = n > 0 ? a + (w - Calendar.weekday(a)) % 7 + 7 * (n - 1) : z - 1 - (Calendar.weekday(z - 1) - w) % 7 - 7 * (-n - 1)
          out << d if d >= a && d < z
        end
        out
      end

      def weekday_ok?(d, a, z)
        w = Calendar.weekday(d)
        @days.include?(w) || @nths.any? { |n, nw| nw == w && (n > 0 ? (d - a) / 7 + 1 == n : (z - 1 - d) / 7 + 1 == -n) }
      end

      def monday(d) = d - (d + 3) % 7

      def month_of(d) = Calendar.civil_from_days(d) / 100 % 100

      def month_index(d)
        ymd = Calendar.civil_from_days(d)
        ymd / 10_000 * 12 + ymd / 100 % 100 - 1
      end

      def year(d) = Calendar.civil_from_days(d) / 10_000
    end

    private_constant :Expand
  end
end
