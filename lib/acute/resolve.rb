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
    # to begin, if any; point is the D1 point of a part of day
    Reading = Struct.new(:begin, :end, :grain, :dst, :point)
    # The same in local wall seconds
    Span = Struct.new(:b, :e, :grain, :point)

    APPROXIMATE = Assumption.for(:approximate)
    FIXED_OFFSET = Assumption.for(:fixed_offset)

    # An empty Array when nothing fits ("feb 30", a weekday that matches no reading)
    def self.call(node, ctx)
      readings(spans(node, ctx), ctx.zone, ctx)
    end

    def self.spans(node, ctx)
      case node
      when G::Clock then Clock.bare(node, ctx)
      when G::DayRef then Day.whole(node, ctx)
      when G::Now
        t = ctx.now_local
        [Span.new(t, t + 1, :second, nil)]
      when G::Date then Dates.spans(node, ctx)
      when G::Within then within(node, ctx)
      when G::Rel then Rel.spans(node, ctx)
      when G::Shift then Shift.spans(node, ctx)
      when G::Range then Ranges.spans(node, ctx)
      when G::Open then Ranges.open(node, ctx)
      when G::Fuzzy then Fuzzy.spans(node, ctx)
      when G::Fiscal then Period.fiscal(node, ctx)
      when G::Approx
        ctx.note(APPROXIMATE) # D14: the exact time, flagged
        spans(node.node, ctx)
      when G::Zoned then zoned(node, ctx)
      else Periodic.bare(node, ctx)
      end
    end

    # "friday 3pm" repeats weekly, so it is found like a weekday; "tomorrow 3pm" is 3pm inside each reading of
    # tomorrow
    def self.within(node, ctx)
      return Periodic.bare(node, ctx) if Periodic.cycle(node.outer)
      out = []
      spans(node.outer, ctx).each do |s|
        Periodic.inside(node.inner, node.outer, s, ctx).each { |x| out << x unless out.any? { |o| o.b == x.b && o.e == x.e } }
      end
      out
    end

    # D18: an offset in the text wins over the zone; D29: a numeric one makes the time machine-written
    def self.zoned(node, ctx)
      ctx.note(FIXED_OFFSET)
      home = ctx.zone
      off = node.offset
      ctx.zone = Zone.for(format("%s%02d:%02d", off < 0 ? "-" : "+", off.abs / 3600, off.abs / 60 % 60))
      ctx.machine = node.numeric
      inner = spans(node.node, ctx)
      there = ctx.zone
      ctx.zone = home
      ctx.machine = false
      readings(inner, there, ctx).map do |r|
        Span.new(r.begin && r.begin + home.offset_at(r.begin), r.end && r.end + home.offset_at(r.end), r.grain,
                 r.point && r.point + home.offset_at(r.point))
      end
    end

    def self.readings(spans, zone, ctx)
      out = []
      spans.each do |s|
        ctx.dst = nil
        b = s.b && zone.local_to_utc(s.b, ctx)
        dst = ctx.dst
        e = s.e && zone.local_to_utc(s.e, ctx)
        point = s.point && zone.local_to_utc(s.point, ctx)
        out << Reading.new(b, e, s.grain, dst, point) unless out.any? { |o| o.begin == b && o.end == e }
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
require_relative "resolve/rel"
require_relative "resolve/shift"
require_relative "resolve/ranges"
require_relative "resolve/fuzzy"
