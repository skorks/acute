require_relative "grammar"
require_relative "assumption"
require_relative "calendar"

module Acute
  # Tree plus context to readings, the main one first. Every convention (the D-rules) lives under resolve/.
  #
  # Inside resolve, times are local wall seconds (Zone's "local"), so day and month arithmetic is plain
  # Integer maths; the readings are converted to UTC once, at the end.
  module Resolve
    G = Grammar
    # begin and end are epochs, end exclusive, either nil when open; dst is the code of a DST adjustment made
    # to begin, if any; point is the D1 point of a part of day; frac the fraction of a second an instant was written with (D47)
    Reading = Struct.new(:begin, :end, :grain, :dst, :point, :frac)
    # The same in local wall seconds. An instant ("now", "in 3 hours", a time with an offset) also carries its
    # UTC in ub and ue, so a wall time the clocks repeat keeps the side it is on; dst is the DST adjustment
    # made converting ub from a zone named in the text (D47)
    Span = Struct.new(:b, :e, :grain, :point, :ub, :ue, :dst)

    APPROXIMATE = Assumption.for(:approximate)
    FIXED_OFFSET = Assumption.for(:fixed_offset)
    AMBIGUOUS_ZONE = Assumption.for(:ambiguous_zone)
    WEEKDAY_MISMATCH = Assumption.for(:weekday_mismatch)

    # An empty Array when nothing fits ("feb 30")
    def self.call(node, ctx)
      list = spans(node, ctx)
      if list.empty? && !(date = Periodic.unfiltered(node)).equal?(node)
        list = mismatch(node, date, ctx)
      end
      readings(list, ctx)
    end

    # D37, D43: a weekday that fits none of a date's coming readings may fit the one just gone ("Thu Aug 10"
    # said on 16 Aug 2006); failing that, the date wins ("Sat, Sep 21" when that is a Tuesday). No other
    # year is searched for.
    def self.mismatch(node, date, ctx)
      unless ctx.past?
        ctx.past = :back
        list = spans(node, ctx)
        ctx.past = false
        return list unless list.empty?
      end
      list = spans(date, ctx)
      # D37: a weekday that fits one of the date's readings picks it ("Sat 16th" said on Wednesday the 16th)
      wday = node
      wday = wday.outer until G::Weekday === wday.inner
      fit = list.select { |s| (s.b.div(Period::DAY) + 4) % 7 == wday.inner.wday }
      unless fit.empty?
        ctx.unnote(Periodic::SAME_DAY) if fit.size < list.size
        return fit
      end
      ctx.note(WEEKDAY_MISMATCH) unless list.empty?
      list
    end

    def self.spans(node, ctx)
      case G::KIND[node.class]
      when :clock then Clock.bare(node, ctx)
      when :day_ref then Day.whole(node, ctx)
      when :now
        t = ctx.now_local
        [Span.new(t, t + 1, :second, nil, ctx.now, ctx.now + 1)]
      when :date then Dates.spans(node, ctx)
      when :within then within(node, ctx)
      when :rel then Rel.spans(node, ctx)
      when :shift then Shift.spans(node, ctx)
      when :counted then Shift.counted(node, ctx)
      when :closest then Shift.closest(node, ctx)
      when :range then Ranges.spans(node, ctx)
      when :open then Ranges.open(node, ctx)
      when :lasting then Ranges.lasting(node, ctx)
      when :holding then Resolve.spans(node.node, ctx).map { |s| Period.unit(node.unit, ctx, s.b) } # D19
      when :fuzzy then Fuzzy.spans(node, ctx)
      when :fiscal then Period.fiscal(node, ctx)
      when :years then Dates.years(node, ctx)
      when :approx
        ctx.note(APPROXIMATE) # D14: the exact time, flagged
        spans(node.node, ctx)
      when :zoned then zoned(node, ctx)
      else Periodic.bare(node, ctx)
      end
    end

    # "friday 3pm" repeats weekly, so it is found like a weekday; "tomorrow 3pm" is 3pm inside each reading of
    # tomorrow
    def self.within(node, ctx)
      return today_in(node.outer.year, ctx) if G::Date === node.outer && node.outer.year && !node.outer.month && today?(node.inner)
      if (cyc = Periodic.cycle(node.outer))
        return Periodic.bare(node, ctx, cyc)
      end
      if G::Shift === node.outer && !node.outer.anchor && (r = shifted(node, ctx))
        return r
      end
      outers = spans(node.outer, ctx)
      return Periodic.inside(node.inner, node.outer, outers[0], ctx) if outers.size == 1
      out = []
      outers.each do |s|
        Periodic.inside(node.inner, node.outer, s, ctx).each { |x| out << x unless out.any? { |o| o.b == x.b && o.e == x.e } }
      end
      # D37, D44: a weekday that fits both orders of a numeric date picks the locale's ("Friday 7/6")
      if out.size > 1 && G::Weekday === node.inner && G::Date === node.outer && node.outer.sep
        ctx.unnote(Dates::ORDER)
        return out.take(1)
      end
      out
    end

    # D44: a recurring day beside a shift from now is the one in its own cycle that holds the shifted instant:
    # "thanksgiving in 9 months", "3 months ago saturday"; an ordinal's is the shift's unit when that is
    # coarser: "first monday in 2 years"
    def self.shifted(node, ctx)
      cyc = Periodic.cycle(node.inner)
      return if !cyc || cyc == :day
      unit = node.outer.unit
      unit = cyc unless ordinal?(node.inner) && G::UNIT_SIZE[unit] > G::UNIT_SIZE[cyc]
      t = Shift.spans(node.outer, ctx)[0].b
      Periodic.inside(node.inner, nil, Period.span(unit, ctx, Period.index(unit, ctx, t)), ctx)
    end

    def self.today?(node)
      (G::DayRef === node && node.offset == 0) || (G::Rel === node && node.word == :this && G::Unit === node.node && node.node.unit == :day)
    end

    # D48: "this day 1800" is today's date in that year
    def self.today_in(year, ctx)
      md = Calendar.civil_from_days(ctx.today) % 10_000
      m = md / 100
      d = md % 100
      return [] if d > Calendar.days_in_month(year, m)
      [Day.day(Calendar.days_from_civil(year, m, d))]
    end

    def self.ordinal?(node)
      case node
      when G::Nth then true
      when G::Within then ordinal?(node.outer)
      when G::Fuzzy then ordinal?(node.node)
      else false
      end
    end

    # D18: an offset in the text wins over the zone, and fixes the instant; D29: a numeric one makes the time
    # machine-written
    def self.zoned(node, ctx)
      off = node.offset
      return named_zone(node, Zone.for(off.name), ctx) if Symbol === off
      return ambiguous_zone(node, off, ctx) unless Integer === off
      ctx.note(FIXED_OFFSET)
      ctx.machine = node.numeric
      inner = ctx.in_zone(Zone.fixed(off)) { spans(node.node, ctx) }
      ctx.machine = false
      zone = ctx.zone
      inner.map do |s|
        ub = s.b && s.b - off
        ue = s.e && s.e - off
        if ub && ue && !s.point && (home = zone.steady_offset(ub, ue))
          Span.new(ub + home, ue + home, s.grain, nil, ub, ue)
        else
          Span.new(ub && ctx.local(ub), ue && ctx.local(ue), s.grain, s.point && ctx.local(s.point - off), ub, ue)
        end
      end
    end

    # D44: under an IANA name in the text the wall times are that zone's, with its own clock changes
    def self.named_zone(node, zone, ctx)
      ctx.note(FIXED_OFFSET)
      inner = ctx.in_zone(zone) { spans(node.node, ctx) }
      inner.map do |s|
        ctx.dst = nil
        ub = s.ub || (s.b && zone.local_to_utc(s.b, ctx, ctx.dst_policy))
        dst = s.ub ? s.dst : ctx.dst
        ue = s.ue || (s.e && zone.local_to_utc(s.e, ctx, ctx.dst_policy))
        point = s.point && zone.local_to_utc(s.point, ctx, ctx.dst_policy)
        Span.new(ub && ctx.local(ub), ue && ctx.local(ue), s.grain, point && ctx.local(point), ub, ue, dst)
      end
    end

    # D38: each of an ambiguous abbreviation's offsets in order; in the country it leads with, the first alone
    def self.ambiguous_zone(node, offs, ctx)
      home = offs[0]
      offs = offs.drop(1) if String === home
      return zoned(G::Zoned.new(node.node, offs[0], false), ctx) if home == ctx.locale.country
      ctx.note(AMBIGUOUS_ZONE)
      offs.flat_map { zoned(G::Zoned.new(node.node, _1, false), ctx) }
    end

    def self.readings(spans, ctx)
      zone = ctx.zone
      frac = ctx.frac
      out = []
      spans.each do |s|
        ctx.dst = nil
        b = s.b
        e = s.e
        point = s.point
        if !s.ub && !s.ue && b && e && (!point || (point >= b && point <= e)) && (off = zone.steady_offset(b, e))
          b -= off
          e -= off
          point -= off if point
          dst = nil
        else
          b = s.ub || (b && zone.local_to_utc(b, ctx, ctx.dst_policy))
          dst = s.ub ? s.dst : ctx.dst
          e = s.ue || (e && zone.local_to_utc(e, ctx, ctx.dst_policy))
          # a start the clocks skipped moved forward by the gap, past the end: it keeps its length
          e = b + (s.e - s.b) if b && e && e <= b
          point &&= zone.local_to_utc(point, ctx, ctx.dst_policy)
        end
        next if !out.empty? && out.any? { |o| o.begin == b && o.end == e }
        out << Reading.new(b, e, s.grain, dst, point, frac && e && b && e - b == 1 ? frac : nil)
      end
      out
    end
  end
end

require_relative "resolve/period"
require_relative "resolve/clock"
require_relative "resolve/day"
require_relative "resolve/dates"
require_relative "resolve/named"
require_relative "resolve/periodic"
require_relative "resolve/nth"
require_relative "resolve/rel"
require_relative "resolve/shift"
require_relative "resolve/ranges"
require_relative "resolve/fuzzy"
