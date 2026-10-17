require_relative "grammar"
require_relative "assumption"

module Acute
  # Tree plus context to readings, the main one first. Every convention (the D-rules) lives under resolve/.
  module Resolve
    # begin and end are epochs, end exclusive; dst is the code of a DST adjustment made to begin, if any
    Reading = Struct.new(:begin, :end, :grain, :dst)

    def self.call(node, ctx)
      case node
      when Grammar::Clock then Clock.bare(node, ctx)
      when Grammar::Moment then Day.moment(node, ctx)
      when Grammar::DayRef then Day.whole(node, ctx)
      else [Reading.new(ctx.now, ctx.now + 1, :second, nil)]
      end
    end
  end
end

require_relative "resolve/clock"
require_relative "resolve/day"
