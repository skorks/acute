require "json"

module Acute
  # A length of time as the parts said, so "1 month" stays a month rather than a guess at its seconds
  class Duration
    # @api private
    UNIT_PART = Ractor.make_shareable(
      { year: [:years, 1], decade: [:years, 10], century: [:years, 100], quarter: [:months, 3], season: [:months, 3], month: [:months, 1],
        week: [:weeks, 1], fortnight: [:weeks, 2], day: [:days, 1], business_day: [:business_days, 1],
        hour: [:hours, 1], minute: [:minutes, 1], second: [:seconds, 1] }
    )
    FIXED = { weeks: 604_800, days: 86_400, hours: 3600, minutes: 60, seconds: 1 }.freeze
    SHORT = Ractor.make_shareable({ years: "y", months: "mo", weeks: "w", business_days: " business days", days: "d",
                                    hours: "h", minutes: "m", seconds: "s" })
    LONG = Ractor.make_shareable({ years: "year", months: "month", weeks: "week", business_days: "business day",
                                   days: "day", hours: "hour", minutes: "minute", seconds: "second" })
    ORDER = SHORT.keys.freeze
    private_constant :FIXED, :SHORT, :LONG, :ORDER
    UNIT = { years: :year, months: :month, weeks: :week, business_days: :business_day, days: :day, hours: :hour,
             minutes: :minute }.freeze

    attr_reader :parts

    # A fraction goes to the next smaller unit: "1.5 hours" is 1h 30m, "3.5 years" 3y 6mo; past seconds it stays
    def self.from_units(units)
      parts = Hash.new(0)
      units.each do |u|
        count = u.count
        unit = u.unit
        loop do
          part, k = UNIT_PART.fetch(unit)
          n = (smaller = Resolve::Period::SMALLER[unit]) ? count.floor : count
          parts[part] += n * k
          break if (count -= n).zero?
          unit, m = smaller
          count *= m
        end
      end
      new(**parts)
    end

    def initialize(**parts)
      unknown = parts.keys - ORDER
      raise ArgumentError, "unknown duration parts: #{unknown.join(", ")}" if unknown.any?
      @parts = ORDER.filter_map { |k| [k, whole(parts[k])] if parts[k] && parts[k] != 0 }.to_h.freeze
      freeze
    end

    def kind = :duration

    # With from:, the seconds from that Time to #after it
    def seconds(from: nil, **ctx)
      return whole(after(from, **ctx).to_r - from.to_r) if from
      calendar = @parts.keys - FIXED.keys
      if calendar.any?
        raise ArgumentError, "a #{LONG[calendar[0]]} has no fixed length; use #after or #seconds(from:)"
      end
      @parts.sum { |k, n| n * FIXED[k] }
    end

    # D47: the Time this long after time, as "<this> from <time>" reads (D23): years and months first, on the
    # calendar, then weeks and days of wall clock, then hours to seconds of elapsed time
    def after(time, zone: nil, context: :future, locale: nil, week_start: nil, hemisphere: nil, fiscal_year_start: nil,
              strict: true, dst: nil, holidays: nil, business_days: nil, year_bias: nil)
      ctx = Context.new(time, zone, context, locale, week_start, hemisphere, fiscal_year_start, strict, dst, holidays,
                        business_days, year_bias)
      seconds = @parts.fetch(:seconds, 0)
      node = @parts.reduce(nil) do |anchor, (part, n)|
        part == :seconds ? anchor : Grammar::Shift.new(n, UNIT[part], anchor)
      end
      node = Grammar::Shift.new(seconds.floor, :second, node) if node.nil? || seconds.floor != 0
      readings = Resolve.call(node, ctx, failure: true)
      raise Explain.error(readings, to_s) if Failure === readings
      epoch = readings[0].begin
      Time.at(epoch, in: ctx.zone.offset_at(epoch)) + (seconds - seconds.floor) + (Time === time ? time.subsec : 0)
    end

    # Weeks alone stay weeks ("P2W"); ISO 8601 has no business days, so those give nil
    def iso8601
      return if @parts.key?(:business_days)
      return "P#{@parts[:weeks]}W" if @parts.keys == [:weeks]
      p = @parts
      days = p.fetch(:days, 0) + p.fetch(:weeks, 0) * 7
      date = [[p[:years], "Y"], [p[:months], "M"], [days.nonzero?, "D"]].filter_map { |n, l| "#{num(n)}#{l}" if n }.join
      time = [[p[:hours], "H"], [p[:minutes], "M"], [p[:seconds], "S"]].filter_map { |n, l| "#{num(n)}#{l}" if n }.join
      "P#{date}#{"T#{time}" unless time.empty?}"
    end

    def to_s(style = :short)
      if style == :short
        return @parts.map { |k, n| k == :business_days && n == 1 ? "1 business day" : "#{num(n)}#{SHORT[k]}" }.join(" ")
      end
      @parts.map { |k, n| "#{num(n)} #{LONG[k]}#{"s" unless n == 1}" }.join(" ")
    end

    # seconds is nil when a part has no fixed length; a fraction of a second is a Float
    def to_h
      fixed = (@parts.keys - FIXED.keys).empty?
      { kind: "duration", parts: @parts.transform_values { json_num(_1) }, iso8601: iso8601,
        seconds: fixed ? json_num(seconds) : nil }
    end

    def to_json(*args) = to_h.to_json(*args)

    def as_json(*) = JSON.parse(to_json)

    def ==(other) = Duration === other && other.parts == @parts

    def inspect = "#<Acute::Duration #{self}>"

    private

    def json_num(n) = Rational === n ? n.to_f : n

    def whole(n) = Rational === n && n.denominator == 1 ? n.to_i : n

    # "123.45s": a fraction of a second as a decimal
    def num(n) = Rational === n ? n.to_f.to_s : n.to_s
  end
end
