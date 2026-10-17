module Acute
  def self.describe(value, now: nil, zone: nil, context: :future, locale: nil, week_start: nil, hemisphere: nil,
                    fiscal_year_start: nil, style: :relative)
    raise ArgumentError, "style: must be :relative or :calendar" unless Describe::STYLES.include?(style)
    return Describe.duration(value) if Duration === value
    zone ||= value.zone if Result === value
    ctx = Context.new(now, zone, context, locale, week_start, hemisphere, fiscal_year_start)
    opts = { now: Time.at(ctx.now), zone: zone || ctx.zone.name, context: context, locale: locale,
             week_start: week_start, hemisphere: hemisphere, fiscal_year_start: fiscal_year_start }
    Describe.new(value, style == :calendar, ctx, opts).text
  end

  # English that Acute.parse reads back as the value given (D45). Candidates come most natural first; each is
  # parsed with the same now, zone and options, and the first that gives the value as its only reading wins.
  # The last candidates write the date, the year, the zone and finally ISO 8601, which always read back.
  class Describe
    STYLES = %i[relative calendar].freeze
    MONTHS = Result::MONTHS
    WEEKDAYS = Result::WEEKDAYS
    MONTH_NAMES = Ractor.make_shareable(%w[January February March April May June July August September October
                                           November December])
    DAY_NAMES = Ractor.make_shareable(%w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday])
    PARTS = Ractor.make_shareable(%w[morning afternoon evening night])
    SEASONS = Ractor.make_shareable(%w[spring summer autumn winter])
    DAY = 86_400

    # Hours, minutes and seconds carried upward ("5400s" is "1h 30m"); never into days, which DST can stretch (D23)
    def self.duration(d)
      p = d.parts
      return d.to_s unless (p.keys & %i[hours minutes seconds]).size > 0
      total = p.fetch(:hours, 0) * 3600 + p.fetch(:minutes, 0) * 60 + p.fetch(:seconds, 0)
      h, rest = total.divmod(3600)
      m, s = rest.divmod(60)
      Duration.new(**p.except(:hours, :minutes, :seconds), hours: h, minutes: m, seconds: s).to_s
    end

    # "9am", "9:30am", "9:00:30am", "12am" for midnight
    def self.clock(secs, meridiem = true)
      h = secs / 3600
      m = secs / 60 % 60
      s = secs % 60
      out = (h % 12 == 0 ? 12 : h % 12).to_s
      out << format(":%02d", m) if m != 0 || s != 0
      out << format(":%02d", s) if s != 0
      out << (h < 12 ? "am" : "pm") if meridiem
      out
    end

    # A value as the span it stands for: an instant, or begin and end with either open
    Target = Struct.new(:b, :e, :point, :instant) do
      def self.for(value, ctx)
        case value
        when Result
          new(value.begin&.to_i, value.end&.to_i, value.time.to_i, value.instant?)
        when Range then range(value, ctx)
        when Date then range(value..value, ctx)
        when DateTime, Time then new(nil, nil, value.to_time.to_i, true)
        else
          raise ArgumentError, "expected a Result, Time, Date, Range or Duration, got #{value.class}" unless value.respond_to?(:time_zone)
          new(nil, nil, value.to_time.to_i, true)
        end
      end

      # The end is exclusive, as in a Result; a Date end includes its day unless the range excludes it
      def self.range(r, ctx)
        b = edge(r.begin, false, ctx)
        e = edge(r.end, !r.exclude_end?, ctx)
        raise ArgumentError, "a range needs at least one end" unless b || e
        raise ArgumentError, "the range runs backwards or is empty (a day the zone skipped is empty)" if b && e && e <= b
        new(b, e, nil, false)
      end

      def self.edge(x, through, ctx)
        case x
        when nil then nil
        when DateTime, Time then x.to_time.to_i
        when Date then ctx.zone.local_to_utc((x.jd - 2_440_588 + (through ? 1 : 0)) * DAY, ctx)
        else
          raise ArgumentError, "a range's ends must be Times or Dates, got #{x.class}" unless x.respond_to?(:time_zone)
          x.to_time.to_i
        end
      end
    end

    def initialize(value, calendar, ctx, opts)
      @calendar = calendar
      @ctx = ctx
      @zone = ctx.zone
      @opts = opts
      @today = ctx.today
      @day_first = ctx.locale.day_first
      t = Target.for(value, ctx)
      @b, @e, @point, @instant = t.b, t.e, t.point, t.instant
    end

    def text
      found = to_enum(:candidates).find { fits?(_1) }
      return found if found
      return @last unless @point && !@instant
      # No part of the day says this span's point, so the span alone is written
      @point = nil
      to_enum(:candidates).find { fits?(_1) } || @last
    end

    private

    def fits?(text)
      @last = text
      r = Acute.parse(text, **@opts)
      return false unless r && !r.ambiguous?
      return !r.span? && r.time.to_i == @point if @instant
      r.begin&.to_i == @b && r.end&.to_i == @e && (@point.nil? || r.time.to_i == @point)
    end

    def candidates(&)
      return instant(@point, &) if @instant
      return before(&) unless @b
      return after(&) unless @e
      part_of_day(&) if @point && @point != @b
      aligned?(@b) && aligned?(@e) ? days(&) : span(&)
    end

    def instant(p)
      if !@calendar
        yield "now" if p == @ctx.now
        w = day_word(day_of(p))
        yield "#{w} at #{clock(secs_of(p))}" if w
      end
      dated(p) { yield _1 }
    end

    # "Sun, Oct 18, 9am", then with the year, its zone's abbreviation, its offset, and ISO 8601
    def dated(p)
      d = day_of(p)
      c = clock(secs_of(p))
      yield "#{date(d, false)}, #{c}"
      at = "#{date(d, true)}, #{c}"
      yield at
      yield "#{at} #{@zone.abbreviation_at(p)}"
      yield "#{at} #{offset(p)}"
      yield iso(p)
    end

    def days_named(d)
      if !@calendar && (w = day_word(d))
        yield w
      end
      yield date(d, false)
      yield date(d, true)
    end

    def after
      if aligned?(@b)
        d = day_of(@b)
        days_named(d) { yield "#{_1} onwards" }
        days_named(d - 1) { yield "after #{_1}" }
      end
      yield "after #{clock(secs_of(@b))}" unless @calendar
      dated(@b) do |x|
        yield "after #{x}"
        yield "#{x} onwards"
      end
    end

    def before
      days_named(day_of(@e)) { yield "before #{_1}" } if aligned?(@e)
      yield "before #{clock(secs_of(@e))}" unless @calendar
      dated(@e) { yield "before #{_1}" }
    end

    # "tonight", "tomorrow morning", "Sun, Oct 18, morning": a part of the day with its point
    def part_of_day
      d = day_of(@point)
      unless @calendar
        if d == @today
          yield "tonight"
          PARTS.each { yield "this #{_1}" }
        end
        yield "last night" if d == @today - 1
        if (w = day_word(d))
          PARTS.each { yield "#{w} #{_1}" }
        end
      end
      [false, true].each { |year| PARTS.each { |part| yield "#{date(d, year)}, #{part}" } }
    end

    # Whole days: a day, a named period, or the first and last days
    def days(&)
      d1 = day_of(@b)
      d2 = day_of(@e)
      return days_named(d1, &) if d2 - d1 == 1
      y1, m1, dd1 = ymd(d1)
      y2, m2, dd2 = ymd(d2)
      months = (y2 - y1) * 12 + m2 - m1
      if d2 - d1 == 7 && Calendar.weekday(d1) == @ctx.week_start
        relative("week", &)
        yield "the week of #{md(d1, false)}"
        yield "the week of #{md(d1, true)}"
      elsif dd1 == 1 && dd2 == 1
        if months == 1
          relative("month", &)
          yield MONTH_NAMES[m1 - 1]
          yield "#{MONTH_NAMES[m1 - 1]} #{y1}"
        elsif months == 3
          if m1 % 3 == 1
            relative("quarter", &)
            yield "Q#{m1 / 3 + 1}"
            yield "Q#{m1 / 3 + 1} #{y1}"
          end
          SEASONS.each { yield "#{_1} #{y1}" }
        elsif m1 == 1 && m2 == 1
          if months == 12
            relative("year", &)
            yield y1.to_s
          end
          yield "the #{y1}s" if months == 120 && y1 % 10 == 0
          yield "#{y1} – #{y2 - 1}"
        end
      end
      yield "#{md(d1, false)} – #{md(d2 - 1, false)}"
      yield "#{md(d1, true)} – #{md(d2 - 1, true)}"
      yield "#{iso(@b)} – #{iso(@e)}"
    end

    def relative(unit)
      return if @calendar
      yield "this #{unit}"
      yield "next #{unit}"
      yield "last #{unit}"
    end

    # A span with clock times: "today, 2–5pm", "since Oct 10, 2pm", "Oct 10, 2pm – Oct 17, 2pm"
    def span
      d1 = day_of(@b)
      s1 = secs_of(@b)
      s2 = secs_of(@e)
      d2 = day_of(@e)
      c1 = clock(s1)
      c2 = clock(s2)
      if !@calendar && @e == @ctx.now
        days_named(d1) { yield "since #{_1}" } if aligned?(@b)
        yield "since #{md(d1, false)}, #{c1}"
        dated(@b) { yield "since #{_1}" }
      end
      if d2 == d1 || (d2 == d1 + 1 && aligned?(@e))
        short = s2 != 0 && (s1 < 43_200) == (s2 < 43_200) ? "#{clock(s1, false)}–#{c2}" : "#{c1}–#{c2}"
        days_named(d1) do |x|
          yield "#{x}, #{short}"
          yield "#{x}, #{c1} – #{c2}"
        end
      end
      if !@calendar && (w1 = day_word(d1)) && (w2 = day_word(d2))
        yield "#{w1}, #{c1} – #{w2}, #{c2}"
      end
      yield "#{md(d1, false)}, #{c1} – #{md(d2, false)}, #{c2}"
      yield "#{md(d1, true)}, #{c1} – #{md(d2, true)}, #{c2}"
      yield "#{md(d1, true)}, #{c1} #{@zone.abbreviation_at(@b)} – #{md(d2, true)}, #{c2} #{@zone.abbreviation_at(@e)}"
      yield "#{iso(@b)} – #{iso(@e)}"
    end

    # "today", "tomorrow", "yesterday", "Friday" up to six days ahead, "last Friday" up to six back
    def day_word(d)
      case d - @today
      when 0 then "today"
      when 1 then "tomorrow"
      when -1 then "yesterday"
      when 2..6 then DAY_NAMES[Calendar.weekday(d)]
      when -6..-2 then "last #{DAY_NAMES[Calendar.weekday(d)]}"
      end
    end

    def ymd(d)
      x = Calendar.civil_from_days(d)
      [x / 10_000, x / 100 % 100, x % 100]
    end

    # "Oct 18" or "18 Oct", with the year: "Oct 18, 2026", "18 Oct 2026"
    def md(d, year)
      y, m, dd = ymd(d)
      @day_first ? "#{dd} #{MONTHS[m - 1]}#{" #{y}" if year}" : "#{MONTHS[m - 1]} #{dd}#{", #{y}" if year}"
    end

    # "Sun, Oct 18" or "Sun 18 Oct"
    def date(d, year)
      wd = WEEKDAYS[Calendar.weekday(d)]
      @day_first ? "#{wd} #{md(d, year)}" : "#{wd}, #{md(d, year)}"
    end

    def clock(secs, meridiem = true) = Describe.clock(secs, meridiem)

    def local(epoch) = epoch + @zone.offset_at(epoch)

    def day_of(epoch) = local(epoch).div(DAY)

    def secs_of(epoch) = local(epoch) % DAY

    def day_start(d) = @zone.local_to_utc(d * DAY, @ctx)

    def aligned?(epoch) = day_start(day_of(epoch)) == epoch

    def offset(epoch)
      o = @zone.offset_at(epoch)
      format("%s%02d:%02d", o < 0 ? "-" : "+", o.abs / 3600, o.abs / 60 % 60)
    end

    def iso(epoch) = Time.at(epoch, in: @zone.offset_at(epoch)).strftime("%FT%T%:z")
  end
end
