module Acute
  # A length of time as the parts said, so "1 month" stays a month rather than a guess at its seconds
  class Duration
    UNIT_PART = { year: [:years, 1], decade: [:years, 10], century: [:years, 100], quarter: [:months, 3],
                  month: [:months, 1], week: [:weeks, 1], fortnight: [:weeks, 2], day: [:days, 1],
                  business_day: [:business_days, 1], hour: [:hours, 1], minute: [:minutes, 1],
                  second: [:seconds, 1] }.freeze
    FIXED = { weeks: 604_800, days: 86_400, hours: 3600, minutes: 60, seconds: 1 }.freeze
    SHORT = { years: "y", months: "mo", weeks: "w", business_days: " business days", days: "d", hours: "h",
              minutes: "m", seconds: "s" }.freeze
    LONG = { years: "year", months: "month", weeks: "week", business_days: "business day", days: "day",
             hours: "hour", minutes: "minute", seconds: "second" }.freeze
    ORDER = SHORT.keys.freeze

    attr_reader :parts

    def self.from_units(units)
      parts = Hash.new(0)
      units.each do |u|
        count, unit = Resolve::Period.whole(u.count, u.unit)
        part, k = UNIT_PART.fetch(unit)
        parts[part] += count * k
      end
      new(**parts)
    end

    def initialize(**parts)
      unknown = parts.keys - ORDER
      raise ArgumentError, "unknown duration parts: #{unknown.join(", ")}" if unknown.any?
      @parts = ORDER.filter_map { |k| [k, parts[k]] if parts[k] && parts[k] != 0 }.to_h.freeze
    end

    def kind = :duration

    def seconds
      calendar = @parts.keys - FIXED.keys
      if calendar.any?
        raise ArgumentError, "a #{LONG[calendar[0]]} has no fixed length; use #after or #seconds(from:)"
      end
      @parts.sum { |k, n| n * FIXED[k] }
    end

    # Weeks alone stay weeks ("P2W"); ISO 8601 has no business days, so those give nil
    def iso8601
      return if @parts.key?(:business_days)
      return "P#{@parts[:weeks]}W" if @parts.keys == [:weeks]
      p = @parts
      days = p.fetch(:days, 0) + p.fetch(:weeks, 0) * 7
      date = [[p[:years], "Y"], [p[:months], "M"], [days.nonzero?, "D"]].filter_map { |n, l| "#{n}#{l}" if n }.join
      time = [[p[:hours], "H"], [p[:minutes], "M"], [p[:seconds], "S"]].filter_map { |n, l| "#{n}#{l}" if n }.join
      "P#{date}#{"T#{time}" unless time.empty?}"
    end

    def to_s(style = :short)
      return @parts.map { |k, n| "#{n}#{SHORT[k]}" }.join(" ") if style == :short
      @parts.map { |k, n| "#{n} #{LONG[k]}#{"s" unless n == 1}" }.join(" ")
    end

    def to_h = { kind: "duration", parts: @parts, iso8601: iso8601 }

    def ==(other) = Duration === other && other.parts == @parts

    def inspect = "#<Acute::Duration #{to_s}>"
  end
end
