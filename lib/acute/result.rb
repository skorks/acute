require "date"
require "json"
require_relative "calendar"

module Acute
  # A parsed time or span. Epochs are kept as Integers; Time objects are built on first use.
  class Result
    DAY_GRAINS = %i[day weekend week month quarter season year decade century].freeze
    MONTHS = Ractor.make_shareable(%w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec])
    WEEKDAYS = Ractor.make_shareable(%w[Sun Mon Tue Wed Thu Fri Sat])
    NO_ASSUMPTIONS = [].freeze
    GRAIN_SECONDS = { second: 1, minute: 60, hour: 3600 }.freeze

    attr_reader :text, :grain, :assumptions

    # readings: the main reading first; the rest become alternatives
    def initialize(text, readings, zone, assumptions)
      main = readings[0]
      @text = text
      @readings = readings
      @point = main.point || main.begin || main.end
      @begin_epoch = main.begin
      @end_epoch = main.end
      @grain = main.grain
      @zone = zone
      @assumptions = assumptions
    end

    def kind = :time

    def time = @time ||= at(@point)

    def begin = @begin_epoch && (@begin ||= at(@begin_epoch))

    def end = @end_epoch && (@end ||= at(@end_epoch))

    def range = self.begin...self.end

    def zone = @zone.name

    def date
      return unless DAY_GRAINS.include?(@grain) && @begin_epoch
      ymd = Calendar.civil_from_days(local(@begin_epoch).div(86_400))
      Date.new(ymd / 10_000, ymd / 100 % 100, ymd % 100)
    end

    def alternatives
      @alternatives ||= @readings.drop(1).map { |r| Result.new(@text, [r], @zone, NO_ASSUMPTIONS) }.freeze
    end

    def ambiguous? = @readings.size > 1

    def instant? = !span?

    # A day or longer, a part of the day, a clock range, or open at one end
    def span? = DAY_GRAINS.include?(@grain) || open? || @end_epoch - @begin_epoch > GRAIN_SECONDS.fetch(@grain, 1)

    def open? = @begin_epoch.nil? || @end_epoch.nil?

    def iso8601 = span? ? "#{iso(self.begin) || ".."}/#{iso(self.end) || ".."}" : iso(time)

    def to_h
      {
        kind: "time", text: @text, time: iso(time), begin: iso(self.begin), end: iso(self.end),
        grain: @grain.to_s, zone: zone,
        assumptions: @assumptions.map { |a| { code: a.code.to_s, rule: a.rule, message: a.message } },
        alternatives: alternatives.map { |r| { time: iso(r.time), begin: iso(r.begin), end: iso(r.end), grain: r.grain.to_s } }
      }
    end

    def to_json(*args) = to_h.to_json(*args)

    # en-US: "Sun, Oct 18, 2026, 9am EDT", or "Sun, Oct 18, 2026, all day"
    def to_s
      local = local(@point)
      days = local.div(86_400)
      ymd = Calendar.civil_from_days(days)
      date = "#{WEEKDAYS[Calendar.weekday(days)]}, #{MONTHS[ymd / 100 % 100 - 1]} #{ymd % 100}, #{ymd / 10_000}"
      return "#{date}, all day" if DAY_GRAINS.include?(@grain)

      secs = local - days * 86_400
      hour = secs / 3600
      clock = (hour % 12 == 0 ? 12 : hour % 12).to_s
      clock << format(":%02d", secs / 60 % 60) if secs % 3600 != 0
      clock << format(":%02d", secs % 60) if @grain == :second && secs % 60 != 0
      "#{date}, #{clock}#{hour < 12 ? "am" : "pm"} #{@zone.abbreviation_at(@point)}"
    end

    def inspect = "#<Acute::Result #{self}>"

    private

    def local(epoch) = epoch + @zone.offset_at(epoch)

    def at(epoch) = Time.at(epoch, in: @zone.offset_at(epoch))

    def iso(t) = t&.strftime("%FT%T%:z")
  end
end
